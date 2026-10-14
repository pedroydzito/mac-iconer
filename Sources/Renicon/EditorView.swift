import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var entry: AppEntry

    var body: some View {
        Form {
            Section {
                HeaderPreview(entry: entry)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Nome") {
                TextField("Nome exibido", text: $entry.customName, prompt: Text(entry.originalName))
                LabeledContent("Nome original", value: entry.originalName)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Imagem") {
                    HStack {
                        Button("Escolher…") { store.chooseIcon(for: entry.id) }
                        if entry.hasCustomIcon {
                            Button("Restaurar Original") { store.resetIcon(for: entry.id) }
                        }
                    }
                }
                Picker("Estilo", selection: $entry.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!entry.hasCustomIcon)
                Toggle(isOn: Binding(
                    get: { entry.applyIconToOriginal },
                    set: { store.setApplyToOriginal($0, for: entry.id) }
                )) {
                    Text("Usar este ícone também no app original")
                    Text("Faz o ícone novo aparecer no Dock enquanto o app está aberto. O Renicon reaplica automaticamente depois de atualizações.")
                }
                .disabled(!entry.hasCustomIcon)
            } header: {
                Text("Ícone")
            } footer: {
                Text("Arraste uma imagem (PNG, JPEG, ICNS…) ou outro app para o ícone acima.")
                    .foregroundStyle(.secondary)
            }

            Section("Informações") {
                LabeledContent("Identificador", value: entry.bundleIdentifier ?? "—")
                LabeledContent("App original") {
                    PathButton(path: entry.originalPath)
                }
                LabeledContent("Atalho") {
                    if let path = entry.shortcutPath {
                        PathButton(path: path)
                    } else {
                        Text("Ainda não criado").foregroundStyle(.secondary)
                    }
                }
                if let date = entry.lastApplied {
                    LabeledContent("Aplicado em", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.displayName)
        .navigationSubtitle(entry.hasPendingChanges ? "Alterações não aplicadas" : "Atualizado")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let path = entry.shortcutPath {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: { Label("Abrir", systemImage: "arrow.up.forward.app") }
                        .help("Abrir o app pelo atalho")
                }
                Button {
                    store.apply(entry.id)
                } label: { Label("Aplicar", systemImage: "checkmark.circle") }
                    .help("Criar ou atualizar o atalho com o novo nome e ícone")
                    .keyboardShortcut("s")
                    .disabled(store.busy)
            }
        }
    }
}

private struct HeaderPreview: View {
    @EnvironmentObject private var store: LibraryStore
    let entry: AppEntry
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 8) {
                Image(nsImage: store.originalIcon(for: entry))
                    .resizable().interpolation(.high)
                    .frame(width: 72, height: 72)
                Text(entry.originalName)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 110)
            }
            Image(systemName: "arrow.right")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tertiary)
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(targeted ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.25),
                                              style: StrokeStyle(lineWidth: 2, dash: entry.hasCustomIcon ? [] : [6, 4]))
                        )
                        .opacity(targeted || !entry.hasCustomIcon ? 1 : 0)
                    Image(nsImage: store.effectiveIcon(for: entry))
                        .resizable().interpolation(.high)
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
                .frame(width: 150, height: 150)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.chooseIcon(for: entry.id) }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    store.setCustomIcon(from: url, for: entry.id)
                    return true
                } isTargeted: { targeted = $0 }
                .help("Arraste uma imagem aqui ou clique duas vezes para escolher")

                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct PathButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 4) {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Mostrar no Finder")
    }
}
