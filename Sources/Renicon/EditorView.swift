import RenCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var entry: AppEntry
    @State private var inDock = true
    @State private var autoApply: Task<Void, Never>?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            IconDropZone(entry: entry)

            SuggestionsRow(entry: entry)

            NameField(entry: $entry, focused: $nameFocused) { applyNow() }

            if let other = store.duplicate(of: entry) {
                Label("“\(other.displayName)” já usa esse nome. Escolha outro.", systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 10) {
            if entry.hasCustomIcon {
                Toggle(isOn: Binding(
                    get: { entry.applyIconToOriginal },
                    set: { store.setApplyToOriginal($0, for: entry.id) }
                )) {
                    Text("Mostrar este ícone também com o app aberto (Dock e ⌘Tab)")
                        .font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Aplica o ícone ao app original. Reaplicado sozinho depois de atualizações.")

                if entry.applyIconToOriginal && store.drawsOwnIcon(entry) {
                    Label("Este app pode mostrar o próprio ícone enquanto está aberto.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            }

            if store.resolvedOriginalURL(for: entry) == nil {
                Label("O app original não foi encontrado. Ele foi apagado?", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            actions

            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Aplica sozinho: logo após trocar o ícone/opções, ou ao terminar de digitar o nome.
        .onChange(of: entry) { _, _ in scheduleAutoApply() }
        .onChange(of: nameFocused) { _, _ in scheduleAutoApply() }
        .onDisappear { if entry.hasPendingChanges && entry.lastApplied != nil { applyNow() } }
        .onChange(of: entry.shortcutPath) { _, _ in inDock = store.isInDock(entry) }
        .onChange(of: entry.applyIconToOriginal) { _, _ in inDock = store.isInDock(entry) }
        // Reconfere quando o usuário volta ao Iconer (pode ter mexido no Dock).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inDock = store.isInDock(entry)
        }
        .onAppear {
            inDock = store.isInDock(entry)
            // Recém-adicionado: já coloca o cursor no nome.
            if entry.lastApplied == nil {
                nameFocused = true
                // Seleciona o nome todo: é só digitar por cima.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
    }

    private var actions: some View {
        GlassGroup(spacing: 14) {
            HStack(spacing: 12) {
                if let path = entry.shortcutPath, !entry.hasPendingChanges {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: {
                        Label("Abrir", systemImage: "arrow.up.forward.app")
                            .padding(.horizontal, 4)
                    }
                    .glassButton()

                    Button {
                        Task {
                            await store.pinToDock(entry.id)
                            inDock = store.isInDock(entry)
                        }
                    } label: {
                        Label(inDock ? "No Dock" : "Pôr no Dock",
                              systemImage: inDock ? "checkmark.rectangle" : "dock.rectangle")
                            .padding(.horizontal, 4)
                    }
                    .glassButton()
                    .disabled(store.busy)
                    .help(inDock ? "Já está no Dock. Clique para atualizar nome e ícone lá."
                                 : "Fixa no Dock com o novo nome e ícone. Ao abrir o app, ele usa este mesmo item do Dock.")
                }

                Button(action: applyNow) {
                    Group {
                        if store.busy {
                            ProgressView().controlSize(.small)
                        } else if entry.hasPendingChanges {
                            Label("Aplicar", systemImage: "checkmark")
                        } else {
                            Label("Aplicado", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .frame(minWidth: 120)
                }
                .glassButton(prominent: entry.hasPendingChanges)
                .keyboardShortcut("s")
                .disabled(store.busy || !entry.hasPendingChanges)
                .help("Cria o atalho com o novo nome e ícone (⌘S)")
            }
            .controlSize(.large)
        }
        .animation(.spring(duration: 0.3), value: entry.hasPendingChanges)
    }

    private func scheduleAutoApply() {
        autoApply?.cancel()
        guard entry.hasPendingChanges, !nameFocused, !store.busy, store.duplicate(of: entry) == nil else { return }
        autoApply = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, entry.hasPendingChanges, !nameFocused, !store.busy else { return }
            await store.apply(entry.id)
        }
    }

    private func applyNow() {
        nameFocused = false
        Task { await store.apply(entry.id) }
    }
}

// MARK: - Ícone

private struct IconDropZone: View {
    @EnvironmentObject private var store: LibraryStore
    let entry: AppEntry
    @State private var hovering = false
    @State private var targeted = false
    @State private var showMaker = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                store.chooseIcon(for: entry.id)
            } label: {
                ZStack {
                    Image(nsImage: store.effectiveIcon(for: entry))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 180, height: 180)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
                        .scaleEffect(targeted ? 1.06 : 1)

                    if hovering || targeted {
                        VStack(spacing: 6) {
                            Image(systemName: targeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                                .font(.system(size: 30, weight: .medium))
                            Text(targeted ? "Solte para usar" : "Trocar ícone")
                                .font(.callout.weight(.semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(width: 210, height: 210)
                .background {
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                        .foregroundStyle(targeted ? Color.accentColor : .white.opacity(entry.hasCustomIcon ? 0 : 0.22))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.spring(duration: 0.25), value: targeted)
            .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in
                store.loadIcon(from: providers, for: entry.id)
            }
            .contextMenu { iconMenu }

            HStack(spacing: 8) {
                Text(entry.hasCustomIcon ? "Clique ou arraste outra imagem para trocar" : "Clique ou arraste uma imagem para o ícone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showMaker = true
                } label: {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(.borderless)
                .help("Criar um ícone com emoji ou letra")
                .accessibilityLabel("Criar ícone com emoji ou letra")
                .popover(isPresented: $showMaker, arrowEdge: .bottom) {
                    IconMakerView { image in
                        store.setCustomIcon(image, for: entry.id, style: .macOS)
                        showMaker = false
                    }
                }
                Menu {
                    iconMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Mais opções de ícone")
            }
        }
    }

    @ViewBuilder
    private var iconMenu: some View {
        Button("Escolher Imagem…") { store.chooseIcon(for: entry.id) }
        Button("Colar Imagem") { store.pasteIcon(for: entry.id) }
        Button("Criar com Emoji ou Letra…") { showMaker = true }
        if entry.hasCustomIcon {
            Divider()
            Button("Usar Ícone Original") { store.resetIcon(for: entry.id) }
        }
    }
}

// MARK: - Sugestões (App Store, WhiteSur) e recentes

private struct SuggestionsRow: View {
    @EnvironmentObject private var store: LibraryStore
    let entry: AppEntry
    @State private var tab = 0  // 0 = Recentes, 1 = Sugestões

    var body: some View {
        let items = store.suggestions[entry.id] ?? []
        let recents = store.recentIcons
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text("Recentes").tag(0)
                Text("Sugestões").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Group {
                if tab == 0 {
                    if recents.isEmpty {
                        placeholder("Os ícones que você usar aparecem aqui.")
                    } else {
                        IconStrip(items: Array(recents.prefix(8)), entryID: entry.id)
                    }
                } else if items.isEmpty && store.loadingSuggestions.contains(entry.id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Buscando sugestões…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(height: 48)
                } else if items.isEmpty {
                    placeholder("Nenhuma sugestão encontrada para este app.")
                } else {
                    IconStrip(items: items, entryID: entry.id)
                }
            }
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: tab)
        .task(id: entry.id) { await store.loadSuggestions(for: entry.id) }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(height: 48)
    }
}

private struct IconStrip: View {
    @EnvironmentObject private var store: LibraryStore
    let items: [IconSuggestions.Suggestion]
    let entryID: AppEntry.ID
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            Task { await store.useSuggestion(item, for: entryID) }
                        } label: {
                            Thumbnail(url: item.url, rounded: !item.isMac)
                                .frame(width: 40, height: 40)
                                .scaleEffect(hovered == item.id ? 1.15 : 1)
                                .animation(.spring(duration: 0.2), value: hovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
                        .help("\(item.name) — \(item.source.label)")
                        .accessibilityLabel("Usar ícone: \(item.name)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560)
            .fixedSize(horizontal: items.count < 10, vertical: false)
        }
        .transition(.opacity)
    }
}

/// Miniatura que carrega PNG, ICNS ou SVG (local ou da internet).
private struct Thumbnail: View {
    let url: URL
    let rounded: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: rounded ? 9 : 0, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08))
            }
        }
        .task(id: url) { image = await IconSuggestions.loadImage(url) }
    }
}

// MARK: - Criar ícone com emoji ou letra

private struct IconMakerView: View {
    var onUse: (NSImage) -> Void
    @State private var text = "😀"
    @State private var color = Color(red: 0.39, green: 0.36, blue: 1)

    private let palette: [Color] = [
        Color(red: 0.39, green: 0.36, blue: 1), .blue, .teal, .green, .yellow, .orange, .red, .pink,
        Color(white: 0.12), .white,
    ]

    private var preview: NSImage {
        IconRenderer.styledImage(IconRenderer.makeIcon(text: text, background: NSColor(color)), style: .macOS, size: 256)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: preview)
                .resizable().interpolation(.high)
                .frame(width: 110, height: 110)
            TextField("Emoji ou letra", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 160)
                .onChange(of: text) { _, value in if value.count > 2 { text = String(value.prefix(2)) } }
            HStack(spacing: 6) {
                ForEach(palette.indices, id: \.self) { i in
                    Circle().fill(palette[i])
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                        .onTapGesture { color = palette[i] }
                }
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
            }
            HStack {
                Button("Emojis…") { NSApp.orderFrontCharacterPalette(nil) }
                Spacer()
                Button("Usar Ícone") { onUse(IconRenderer.makeIcon(text: text, background: NSColor(color))) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

// MARK: - Nome

private struct NameField: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var entry: AppEntry
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    /// Estado do app quando a edição do nome começou (para o ⌘Z voltar ao nome anterior).
    @State private var editStart: AppEntry?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(focused.wrappedValue ? Color.accentColor : .secondary)
            TextField("Digite o novo nome", text: $entry.customName)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused(focused)
                .onSubmit(onSubmit)
            if entry.customName != entry.originalName {
                Button {
                    store.update(entry.id, actionName: "Restaurar Nome") { $0.customName = $0.originalName }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Voltar para “\(entry.originalName)”")
                .accessibilityLabel("Voltar ao nome original")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 400)
        .glass(in: Capsule(), interactive: true)
        .overlay(
            Capsule().stroke(Color.accentColor.opacity(focused.wrappedValue ? 0.8 : 0), lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.15), value: focused.wrappedValue)
        .onReceive(NotificationCenter.default.publisher(for: .reniconCancelEditing)) { _ in
            // Esc: desfaz o que foi digitado e sai do campo.
            if let start = editStart { entry.customName = start.customName }
            editStart = nil
            focused.wrappedValue = false
        }
        .onChange(of: focused.wrappedValue) { _, isFocused in
            if isFocused {
                editStart = entry
            } else if let start = editStart, start.customName != entry.customName {
                store.registerUndo(id: entry.id, restoring: start, iconData: nil, actionName: "Renomear")
                editStart = nil
            }
        }
        .help("Clique para digitar o nome que vai aparecer no Spotlight, Launchpad e Dock")
    }
}

// MARK: - Painel de informações (botão “i”)

struct InfoPanel: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var entry: AppEntry
    var dismiss: () -> Void
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Formato do ícone").font(.headline)
                Picker("Formato do ícone", selection: undoable(\.iconStyle, "Formato do Ícone")) {
                    ForEach(IconStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!entry.hasCustomIcon)
                Text("“Formato macOS” recorta a imagem no formato padrão dos ícones do Mac.")
                    .font(.caption).foregroundStyle(.secondary)

                if entry.hasCustomIcon && entry.iconStyle == .macOS {
                    HStack(spacing: 10) {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                        Slider(value: undoable(\.adjustments.zoom, "Zoom do Ícone"), in: 0.5...1.6)
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                        Text("\(Int(entry.adjustments.zoom * 100))%")
                            .monospacedDigit().font(.caption).frame(width: 38, alignment: .trailing)
                    }
                    HStack {
                        ColorPicker("Cor de fundo", selection: Binding(
                            get: { Color(nsColor: entry.adjustments.backgroundColor) },
                            set: { color in
                                store.update(entry.id, actionName: "Cor de Fundo") { $0.adjustments.background = NSColor(color).hexString }
                            }
                        ), supportsOpacity: false)
                        Spacer()
                        Button("Redefinir") {
                            store.update(entry.id, actionName: "Redefinir Ajustes") { $0.adjustments = IconAdjustments() }
                        }
                            .controlSize(.small)
                            .disabled(entry.adjustments == IconAdjustments())
                    }
                    .font(.callout)
                }
            }

            Toggle(isOn: Binding(
                get: { entry.applyIconToOriginal },
                set: { store.setApplyToOriginal($0, for: entry.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usar o ícone também no app original")
                    Text("Mostra o ícone novo no Dock enquanto o app está aberto. Reaplicado sozinho após atualizações.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!entry.hasCustomIcon)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                row("Nome original", entry.originalName)
                row("Identificador", entry.bundleIdentifier ?? "—")
                row("App original", (entry.originalPath as NSString).abbreviatingWithTildeInPath)
                row("Atalho", entry.shortcutPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Ainda não criado")
                if let date = entry.lastApplied {
                    row("Aplicado em", date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            HStack {
                Button("Original no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
                }
                if let path = entry.shortcutPath {
                    Button("Atalho no Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Spacer()
                Button("Remover…", role: .destructive) { confirmRemoval = true }
                    .foregroundStyle(.red)
                    .confirmationDialog("Remover “\(entry.displayName)”?", isPresented: $confirmRemoval) {
                        Button("Remover", role: .destructive) {
                            let id = entry.id
                            dismiss()
                            store.remove(id)
                        }
                    } message: {
                        Text("O atalho é apagado e o app original volta a ter o nome e o ícone de sempre.")
                    }
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(width: 380)
    }

    private func undoable<T: Equatable>(_ keyPath: WritableKeyPath<AppEntry, T>, _ actionName: String) -> Binding<T> {
        Binding(
            get: { entry[keyPath: keyPath] },
            set: { value in store.update(entry.id, actionName: actionName) { $0[keyPath: keyPath] = value } }
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
        .font(.caption)
    }
}
