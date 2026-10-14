import AppKit
import RenCore

/// Instala e mantém o ajudante do Dock (um LaunchAgent invisível que só reage quando
/// um app personalizado abre ou fecha). Sem apps personalizados, ele é removido.
enum DockHelperInstaller {
    private static var binaryURL: URL { DockSwap.supportURL.appendingPathComponent("RenDockHelper") }
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(DockSwap.helperLabel).plist")
    }
    private static var domain: String { "gui/\(getuid())" }

    static func update(_ items: [DockSwapItem]) {
        DockSwap.save(items)
        guard !items.isEmpty else { uninstall(); return }

        let fm = FileManager.default
        guard let bundled = Bundle.main.url(forResource: "RenDockHelper", withExtension: nil) else { return }
        var binaryChanged = false
        if (try? Data(contentsOf: bundled)) != (try? Data(contentsOf: binaryURL)) {
            try? fm.removeItem(at: binaryURL)
            try? fm.copyItem(at: bundled, to: binaryURL)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
            binaryChanged = true
        }

        let plist: [String: Any] = [
            "Label": DockSwap.helperLabel,
            "ProgramArguments": [binaryURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        if data != (try? Data(contentsOf: agentURL)) {
            try? fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data?.write(to: agentURL, options: .atomic)
            binaryChanged = true
        }

        if !isLoaded {
            _ = try? Shell.run("/bin/launchctl", ["bootstrap", domain, agentURL.path])
        } else if binaryChanged {
            _ = try? Shell.run("/bin/launchctl", ["kickstart", "-k", "\(domain)/\(DockSwap.helperLabel)"])
        }
        DistributedNotificationCenter.default().postNotificationName(
            DockSwap.reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func uninstall() {
        _ = try? Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(DockSwap.helperLabel)"])
        try? FileManager.default.removeItem(at: agentURL)
        try? FileManager.default.removeItem(at: binaryURL)
    }

    private static var isLoaded: Bool {
        (try? Shell.run("/bin/launchctl", ["print", "\(domain)/\(DockSwap.helperLabel)"])) != nil
    }
}
