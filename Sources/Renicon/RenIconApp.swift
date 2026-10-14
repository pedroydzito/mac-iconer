import AppKit
import ServiceManagement
import SwiftUI

@main
struct RenIconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LibraryStore()
    @StateObject private var updater = Updater()
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        Window("Renicon", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updater)
                .onAppear {
                    delegate.store = store
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

        MenuBarExtra("Renicon", systemImage: "app.badge.checkmark", isInserted: $showMenuBar) {
            Button("Abrir Renicon") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
            }
            Button("Verificar Apps Agora") { store.sync() }
            Button("Procurar Atualizações…") { Task { await updater.check(userInitiated: true) } }
            Divider()
            Button("Sair") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    private var timer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["keepRunning": true, "showMenuBar": true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Quando um app termina de atualizar ele costuma ser reaberto — boa hora para conferir.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleSync(after: 2)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleSync(after: 5)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.scheduleSync(after: 0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "keepRunning")
    }

    private var pending: DispatchWorkItem?
    private func scheduleSync(after seconds: Double) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.store?.sync() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
