import AppKit

// Executável dos atalhos criados pelo Iconer. Lê o app original no próprio Info.plist,
// recoloca o ícone personalizado se uma atualização o apagou e abre o app original
// (repassando arquivos soltos sobre o atalho). Não fica rodando: encerra logo em seguida.

final class Launcher: NSObject, NSApplicationDelegate {
    private let info = Bundle.main.infoDictionary ?? [:]
    private var pendingFiles: [URL] = []
    private var didLaunch = false

    private var bundleID: String? { (info["RENOriginalBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    private var originalPath: String { info["RENOriginalPath"] as? String ?? "" }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFiles.append(contentsOf: urls)
        if didLaunch { openOriginal() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didLaunch = true
        // Dá um instante para receber arquivos arrastados sobre o atalho.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.openOriginal() }
    }

    private func originalURL() -> URL? {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        return FileManager.default.fileExists(atPath: originalPath) ? URL(fileURLWithPath: originalPath) : nil
    }

    private func reapplyIconIfNeeded(at app: URL) {
        guard info["RENReapplyIcon"] as? Bool == true,
              let script = info["RENReapplyScript"] as? String,
              let id = info["RENEntryID"] as? String,
              !FileManager.default.fileExists(atPath: app.appendingPathComponent("Icon\r").path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script, id]
        try? process.run()
        process.waitUntilExit()
    }

    private func openOriginal() {
        guard let app = originalURL() else {
            let alert = NSAlert()
            alert.messageText = "O app original não foi encontrado"
            alert.informativeText = "Abra o Iconer para verificar este atalho."
            alert.alertStyle = .warning
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        reapplyIconIfNeeded(at: app)
        let files = pendingFiles
        pendingFiles = []
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let done: (NSRunningApplication?, Error?) -> Void = { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        if files.isEmpty {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: done)
        } else {
            NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration, completionHandler: done)
        }
        // Garantia: encerra mesmo se o macOS não responder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = Launcher()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
