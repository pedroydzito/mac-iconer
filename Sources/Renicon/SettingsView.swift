import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var updater: Updater
    @AppStorage("keepRunning") private var keepRunning = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            store.errorMessage = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Continuar rodando ao fechar a janela", isOn: $keepRunning)
                Toggle("Mostrar na barra de menus", isOn: $showMenuBar)
            } header: {
                Text("Geral")
            } footer: {
                Text("Com o Renicon rodando, ele percebe quando um app é atualizado e reaplica o ícone personalizado automaticamente.")
                    .foregroundStyle(.secondary)
            }

            Section("Atalhos") {
                LabeledContent("Pasta") {
                    Button("Mostrar no Finder") {
                        try? FileManager.default.createDirectory(at: ShortcutBuilder.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ShortcutBuilder.folder)
                    }
                }
                LabeledContent("Manutenção") {
                    HStack {
                        Button("Verificar Agora") { store.sync() }
                        Button("Recriar Todos") { store.applyAll() }
                    }
                }
                LabeledContent("Dock") {
                    Button("Recarregar Dock") { store.reloadDock() }
                }
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
