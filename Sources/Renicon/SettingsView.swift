import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
