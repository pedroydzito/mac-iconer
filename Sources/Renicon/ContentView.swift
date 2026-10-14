import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var search = ""
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(search: search)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            if let id = store.selection, let entry = store.binding(for: id) {
                EditorView(entry: entry)
                    .id(id)
            } else {
                EmptyStateView()
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Buscar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.chooseApps() } label: {
                    Label("Adicionar App", systemImage: "plus")
                }
                .help("Adicionar apps para personalizar")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
            store.add(urls: apps)
            return !apps.isEmpty
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .alert("Algo deu errado", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    let search: String

    private var filtered: [AppEntry] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.originalName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(selection: $store.selection) {
            Section("Apps Personalizados") {
                ForEach(filtered) { entry in
                    SidebarRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button("Aplicar Alterações") { store.apply(entry.id) }
                            if let path = entry.shortcutPath {
                                Button("Abrir") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                                Button("Mostrar Atalho no Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }
                            }
                            Button("Mostrar Original no Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
                            }
                            Divider()
                            Button("Remover", role: .destructive) { store.remove(entry.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { if let id = store.selection { store.remove(id) } }
        .safeAreaInset(edge: .bottom) {
            if !store.entries.isEmpty {
                HStack {
                    Text("\(store.entries.count) \(store.entries.count == 1 ? "app" : "apps")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Aplicar Tudo") { store.applyAll() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
}

struct SidebarRow: View {
    @EnvironmentObject private var store: LibraryStore
    let entry: AppEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: store.effectiveIcon(for: entry))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .lineLimit(1)
                if entry.displayName != entry.originalName {
                    Text(entry.originalName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.hasPendingChanges {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .help("Alterações não aplicadas")
            }
        }
        .padding(.vertical, 3)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        ContentUnavailableView {
            Label("Arraste um app para cá", systemImage: "square.and.arrow.down.on.square")
        } description: {
            Text("Escolha um novo nome e ícone. O Renicon cria um atalho que aparece no Spotlight, no Launchpad e no Dock — e o app original continua atualizando normalmente.")
        } actions: {
            Button("Escolher App…") { store.chooseApps() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
