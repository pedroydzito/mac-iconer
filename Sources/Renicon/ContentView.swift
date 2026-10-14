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

            Group {
                if let id = store.selection, let entry = store.binding(for: id) {
                    EditorView(entry: entry)
                        .id(id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if store.entries.isEmpty {
                    EmptyDropView(targeted: dropTargeted)
                        .transition(.opacity)
                } else {
                    HomeView(targeted: dropTargeted)
                        .transition(.move(edge: .leading).combined(with: .opacity))
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

// MARK: - Início (todos os apps)

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    let targeted: Bool
    @State private var pendingRemoval: AppEntry?

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seus apps")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Clique em um app para editar, ou solte outro app aqui para adicionar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.chooseApps()
                } label: {
                    Label("Adicionar", systemImage: "plus")
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .help("Adicionar app (⌘O)")
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(store.entries) { entry in
                        card(entry)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            }
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog(
            "Remover “\(pendingRemoval?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remover", role: .destructive) {
                if let id = pendingRemoval?.id { store.remove(id) }
            }
        } message: {
            Text("O atalho é apagado e o app original volta a ter o nome e o ícone de sempre.")
        }
    }

    private func card(_ entry: AppEntry) -> some View {
        Button {
            store.selection = entry.id
        } label: {
            VStack(spacing: 10) {
                Image(nsImage: store.effectiveIcon(for: entry))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                VStack(spacing: 2) {
                    Text(entry.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.hasPendingChanges ? "Não aplicado" : "Aplicado")
                        .font(.caption)
                        .foregroundStyle(entry.hasPendingChanges ? Color.accentColor : .secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .contextMenu {
            Button("Editar") { store.selection = entry.id }
            Button("Aplicar") { Task { await store.apply(entry.id) } }
            Button("Mostrar Original no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
            }
            Divider()
            Button("Remover do Renicon…", role: .destructive) { pendingRemoval = entry }
        }
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

