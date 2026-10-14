import AppKit

/// Mantém o ícone personalizado no app original *sem o Renicon estar aberto*.
///
/// - Um script JXA (`reapply.js`) recoloca o ícone quando ele some (após uma atualização).
/// - Uma regra do launchd (WatchPaths) chama esse script só quando a pasta do app muda;
///   não há nenhum processo rodando em segundo plano.
/// - O próprio atalho também chama o script antes de abrir o app.
enum AutoReapply {
    static let label = "com.renicon.reapply"

    static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renicon", isDirectory: true)
    }
    static var scriptURL: URL { supportURL.appendingPathComponent("reapply.js") }
    private static var manifestURL: URL { supportURL.appendingPathComponent("reapply.json") }
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    struct Item: Codable {
        let id: String
        let bundleID: String?
        let path: String
        let icon: String
    }

    /// Reescreve o manifesto e a regra do launchd a partir da lista atual.
    static func update(_ items: [Item]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: manifestURL, options: .atomic)
        }

        unloadAgent()
        guard !items.isEmpty else {
            try? fm.removeItem(at: agentURL)
            return
        }
        let folders = Set(items.map { ($0.path as NSString).deletingLastPathComponent })
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/osascript", "-l", "JavaScript", scriptURL.path],
            "WatchPaths": Array(folders).sorted(),
            "RunAtLoad": true,
            "ThrottleInterval": 10,
            "ProcessType": "Background",
            "LowPriorityIO": true,
        ]
        do {
            try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            try Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
        } catch {
            NSLog("Renicon: não foi possível registrar a regra do launchd: \(error)")
        }
    }

    private static func unloadAgent() {
        try? Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    }

    /// Script executado pelo launchd e pelos atalhos. Argumento opcional: id de um único app.
    private static let script = #"""
    ObjC.import('AppKit');
    function run(argv) {
        const fm = $.NSFileManager.defaultManager;
        const home = ObjC.unwrap($.NSHomeDirectory());
        const manifest = home + '/Library/Application Support/Renicon/reapply.json';
        const data = $.NSData.dataWithContentsOfFile(manifest);
        if (data.isNil()) return;
        const text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
        const ws = $.NSWorkspace.sharedWorkspace;
        const only = argv.length > 0 ? argv[0] : null;
        JSON.parse(text).forEach(function (item) {
            if (only && item.id !== only) return;
            let path = item.path;
            if (item.bundleID) {
                const url = ws.URLForApplicationWithBundleIdentifier(item.bundleID);
                if (!url.isNil()) path = ObjC.unwrap(url.path);
            }
            if (!fm.fileExistsAtPath(path)) return;
            if (fm.fileExistsAtPath(path + '/Icon\r')) return;
            const image = $.NSImage.alloc.initWithContentsOfFile(item.icon);
            if (image.isNil()) return;
            ws.setIconForFileOptions(image, path, 0);
        });
    }
    """#
}

import ServiceManagement

enum SMAppServiceBridge {
    static func unregisterIfNeeded() throws {
        if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
    }
}
