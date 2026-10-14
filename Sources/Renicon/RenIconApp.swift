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
                Button("Aplicar Tudo") { store.applyAll() }
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
        if #available(macOS 13.0, *) {
            try? SMAppServiceBridge.unregisterIfNeeded()
        }
    }
}
