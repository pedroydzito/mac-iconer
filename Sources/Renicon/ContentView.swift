import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.undoManager) private var undoManager
    @State private var dropTargeted = false
    @State private var showInfo = false

    private var selectedEntry: AppEntry? {
        store.selection.flatMap { id in store.entries.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            Backdrop(image: selectedEntry.map { store.effectiveIcon(for: $0) })

            VStack(spacing: 0) {
                if let id = store.selection, let entry = store.binding(for: id) {
                    EditorView(entry: entry)
                        .id(id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    EmptyDropView(targeted: dropTargeted)
                        .transition(.opacity)
                }
                if !store.entries.isEmpty {
                    AppShelf()
                        .padding(.bottom, 18)
                }
            }
            .animation(.spring(duration: 0.35), value: store.selection)
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        // A barra existe nas duas telas para os botões da janela não mudarem de lugar.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if store.selection != nil {
                    Button {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            store.selection = nil
                        } label: {
                            Label("Voltar", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 6)
                        }
                        .keyboardShortcut(.cancelAction)
                        .help("Voltar ao início (Esc)")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let id = store.selection, let entry = store.binding(for: id) {
                    Button {
                        showInfo.toggle()
                    } label: {
                        Label("Detalhes", systemImage: "info.circle")
                    }
                    .accessibilityLabel("Detalhes e opções")
                    .help("Detalhes e opções")
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                        InfoPanel(entry: entry) { showInfo = false }
                    }
                } else {
                    Button {
                        store.chooseApps()
                    } label: {
                        Label("Adicionar App", systemImage: "plus")
                    }
                    .help("Adicionar app (⌘O)")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 600)
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
            store.add(urls: apps)
            return !apps.isEmpty
        } isTargeted: { dropTargeted = $0 }
        // Erros e confirmações em avisos discretos, sem janelas que travam a tela.
        .overlay(alignment: .top) {
            if let message = store.errorMessage {
                Banner(text: message, systemImage: "exclamationmark.triangle.fill", tint: .orange) {
                    store.errorMessage = nil
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    if store.errorMessage == message { store.errorMessage = nil }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glass(in: Capsule())
                    .padding(.bottom, store.entries.isEmpty ? 24 : 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.35), value: store.errorMessage)
        .animation(.spring(duration: 0.35), value: store.toast)
        .background {
            // Atalhos: ⌥⌘← / ⌥⌘→ trocam de app.
            Group {
                Button("") { store.selectAdjacent(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("") { store.selectAdjacent(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshAfterActivation()
        }
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Estado vazio

struct EmptyDropView: View {
    @EnvironmentObject private var store: LibraryStore
    let targeted: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
                    .foregroundStyle(targeted || hovering ? Color.accentColor.opacity(targeted ? 1 : 0.7) : .white.opacity(0.25))
                Image(systemName: targeted ? "plus.app.fill" : "square.and.arrow.down")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.6))
                    .symbolEffect(.bounce, value: targeted)
            }
            .frame(width: 200, height: 200)
            .glass(in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            .scaleEffect(targeted ? 1.06 : hovering ? 1.03 : 1)
            .shadow(color: Color.accentColor.opacity(hovering || targeted ? 0.35 : 0), radius: 30)
            .animation(.spring(duration: 0.3), value: targeted)
            .animation(.spring(duration: 0.3), value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { store.chooseApps() }
            .help("Clique para escolher um app, ou arraste um app até aqui")

            VStack(spacing: 8) {
                Text("Solte um app aqui")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Arraste um ou vários apps da pasta Aplicativos para mudar o nome e o ícone.\nO app original continua atualizando normalmente.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                store.chooseApps()
            } label: {
                Label("Escolher App", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Prateleira de apps (estilo Dock)

struct AppShelf: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var hovered: AppEntry.ID?
    @State private var pendingRemoval: AppEntry?

    var body: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.entries) { entry in
                                shelfItem(entry).id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: store.selection) { _, id in
                        guard let id else { return }
                        withAnimation(.spring(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .frame(width: min(CGFloat(store.entries.count) * 60 + 10, 520))
                .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Button {
                    store.chooseApps()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glass(in: Circle(), interactive: true)
                .help("Adicionar app (⌘O)")
                .accessibilityLabel("Adicionar app")
            }
        }
    }

    private func shelfItem(_ entry: AppEntry) -> some View {
        let selected = store.selection == entry.id
        return Button {
            store.selection = entry.id
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: store.effectiveIcon(for: entry))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .scaleEffect(hovered == entry.id ? 1.12 : 1)
                if entry.hasPendingChanges {
                    Circle().fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                        .offset(x: 2, y: -2)
                }
            }
            .padding(5)
            .background(selected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
        .animation(.spring(duration: 0.2), value: hovered)
        .help(entry.displayName)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Aplicar") { Task { await store.apply(entry.id) } }
            Button("Mostrar Original no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
            }
            Divider()
            Button("Remover do Renicon…", role: .destructive) { pendingRemoval = entry }
        }
        .confirmationDialog(
            "Remover “\(pendingRemoval?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingRemoval?.id == entry.id }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remover", role: .destructive) {
                if let id = pendingRemoval?.id { store.remove(id) }
            }
        } message: {
            Text("O atalho é apagado e o app original volta a ter o nome e o ícone de sempre.")
        }
    }
}

// MARK: - Aviso

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Fechar aviso")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint.opacity(0.25))
    }
}

extension Notification.Name {
    static let reniconCancelEditing = Notification.Name("reniconCancelEditing")
}
