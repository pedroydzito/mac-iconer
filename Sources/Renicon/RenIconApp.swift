import AppKit
import SwiftUI

@main
struct RenIconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LibraryStore()
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("Renicon", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updater)
                .onAppear {
                    store.sync()
                    updater.start()
                }
                .sheet(item: Binding(get: { updater.available }, set: { updater.available = $0 })) { release in
                    UpdateSheet(release: release).environmentObject(updater)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Procurar Atualizações…") { Task { await updater.check(userInitiated: true) } }
            }
            CommandGroup(after: .newItem) {
                Button("Adicionar App…") { store.chooseApps() }
                    .keyboardShortcut("o")
                Button("Aplicar Tudo") { Task { await store.applyAll() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(updater)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // O Renicon não precisa ficar aberto: fechou a janela, o app fecha.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Versões antigas podiam se registrar para abrir no login; desfaz isso.
        try? SMAppServiceBridge.unregisterIfNeeded()
        offerMoveToApplications()
    }

    /// Se o Renicon foi aberto do DMG ou de Downloads, oferece movê-lo para Aplicativos
    /// (necessário para as atualizações automáticas funcionarem).
    private func offerMoveToApplications() {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !path.hasPrefix("/Applications/"), !path.hasPrefix(home + "/Applications/"),
              !path.contains("/.build/"), !UserDefaults.standard.bool(forKey: "dontOfferMove") else { return }

        let alert = NSAlert()
        alert.messageText = "Mover o Renicon para a pasta Aplicativos?"
        alert.informativeText = "Assim ele fica junto dos outros apps e consegue se atualizar sozinho."
        alert.addButton(withTitle: "Mover para Aplicativos")
        alert.addButton(withTitle: "Agora Não")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Não perguntar de novo"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "dontOfferMove") }
        guard response == .alertFirstButtonReturn else { return }

        let destination = "/Applications/Renicon.app"
        do {
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: destination), resultingItemURL: nil)
            }
            try Shell.run("/usr/bin/ditto", [path, destination])
            try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination])
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", destination]
            try process.run()
            exit(0)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Não foi possível mover o Renicon. Arraste-o manualmente para a pasta Aplicativos."
            failure.runModal()
        }
    }
}
