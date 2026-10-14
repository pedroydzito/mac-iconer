import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var updater: Updater
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Pasta") {
                    Button("Mostrar no Finder") {
                        try? FileManager.default.createDirectory(at: ShortcutBuilder.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ShortcutBuilder.folder)
                    }
                }
                LabeledContent("Manutenção") {
                    HStack {
                        Button("Verificar Agora") { store.sync() }
                        Button("Recriar Todos") { Task { await store.applyAll() } }
                    }
                }
                LabeledContent("Dock") {
                    Button("Recarregar Dock") { store.reloadDock() }
                }
                LabeledContent("Desfazer tudo") {
                    Button("Remover Todos os Atalhos…", role: .destructive) { confirmReset = true }
                        .disabled(store.entries.isEmpty)
                        .confirmationDialog("Remover todos os atalhos?", isPresented: $confirmReset) {
                            Button("Remover Tudo", role: .destructive) { store.removeAll() }
                        } message: {
                            Text("Apaga todos os atalhos criados pelo Renicon e devolve os ícones originais dos apps. Use antes de desinstalar o Renicon.")
                        }
                }
            } header: {
                Text("Atalhos")
            } footer: {
                Text("O Renicon não precisa ficar aberto. Os atalhos funcionam sozinhos e, se uma atualização apagar o ícone de um app, o macOS chama um pequeno script que o recoloca — sem nada rodando em segundo plano.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Versão", value: Updater.currentVersion)
                Toggle("Procurar atualizações automaticamente", isOn: $updater.autoCheck)
                LabeledContent {
                    HStack {
                        switch updater.phase {
                        case .checking: ProgressView().controlSize(.small)
                        case .upToDate: Text("Você está na versão mais recente.").foregroundStyle(.secondary)
                        case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
                        default: EmptyView()
                        }
                        Button("Procurar Agora") { Task { await updater.check(userInitiated: true) } }
                            .disabled(updater.phase == .checking)
                    }
                } label: {
                    if let date = updater.lastCheck {
                        Text("Última verificação: \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Atualizações")
                    }
                }
            } header: {
                Text("Atualizações do Renicon")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
