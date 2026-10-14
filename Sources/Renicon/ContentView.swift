import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.undoManager) private var undoManager
    @State private var dropTargeted = false

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
            .padding(.top, 28)
            .animation(.spring(duration: 0.35), value: store.selection)
        }
        .frame(minWidth: 640, minHeight: 600)
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
            store.add(urls: apps)
            return !apps.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .alert("Algo deu errado", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
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

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
                    .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.25))
                Image(systemName: targeted ? "plus.app.fill" : "square.and.arrow.down")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.6))
                    .symbolEffect(.bounce, value: targeted)
            }
            .frame(width: 200, height: 200)
            .glass(in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            .scaleEffect(targeted ? 1.05 : 1)
            .animation(.spring(duration: 0.3), value: targeted)

            VStack(spacing: 8) {
                Text("Solte um app aqui")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Arraste qualquer app da pasta Aplicativos para mudar o nome e o ícone dele.\nO app original continua atualizando normalmente.")
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.entries) { entry in
                            shelfItem(entry)
                        }
                    }
                    .padding(8)
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
