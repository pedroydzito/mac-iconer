import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var entry: AppEntry
    @State private var inDock = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            IconDropZone(entry: entry)

            NameField(entry: $entry, focused: $nameFocused) { applyNow() }

            VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { entry.renameOriginal },
                set: { store.setRenameOriginal($0, for: entry.id) }
            )) {
                Text("Usar o novo nome no próprio app (Dock e Finder com o app fechado)")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Renomeia o arquivo do app original (ex.: “\(entry.originalName).app” → “\(entry.displayName).app”). Não altera o conteúdo nem a assinatura do app; desligar devolve o nome original.")

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
        .onChange(of: entry.shortcutPath) { _, _ in inDock = store.isInDock(entry) }
        .onChange(of: entry.applyIconToOriginal) { _, _ in inDock = store.isInDock(entry) }
        // Reconfere quando o usuário volta ao Renicon (pode ter mexido no Dock).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inDock = store.isInDock(entry)
        }
        .onAppear {
            inDock = store.isInDock(entry)
            // Recém-adicionado: já coloca o cursor no nome.
            if entry.lastApplied == nil { nameFocused = true }
        }
    }

    private var actions: some View {
        GlassGroup(spacing: 14) {
            HStack(spacing: 12) {
                if let path = entry.shortcutPath ?? (entry.renameOriginal ? store.resolvedOriginalURL(for: entry)?.path : nil),
                   !entry.hasPendingChanges {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: {
                        Label("Abrir", systemImage: "arrow.up.forward.app")
                            .padding(.horizontal, 4)
                    }
                    .glassButton()

                    Button {
                        store.pinToDock(entry.id)
                        inDock = true
                    } label: {
                        Label(inDock ? "No Dock" : "Pôr no Dock",
                              systemImage: inDock ? "checkmark.rectangle" : "dock.rectangle")
                            .padding(.horizontal, 4)
                    }
                    .glassButton()
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
        if entry.hasCustomIcon {
            Divider()
            Button("Usar Ícone Original") { store.resetIcon(for: entry.id) }
        }
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
