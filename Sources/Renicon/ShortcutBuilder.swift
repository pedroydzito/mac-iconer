import AppKit

/// Cria o "app atalho": um pacote .app leve, com nome e ícone próprios, que apenas
/// abre o app original. Como ele aponta para o *bundle identifier* (e não para o
/// arquivo), o app original pode ser atualizado ou movido sem quebrar nada.
enum ShortcutBuilder {
    /// ~/Applications: pasta que o Spotlight e o Launchpad sempre indexam.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    /// Pasta usada até a versão 1.2 (os atalhos são migrados automaticamente).
    static var legacyFolder: URL { folder.appendingPathComponent("Renicon", isDirectory: true) }

    static func isOurShortcut(_ url: URL) -> Bool {
        (Bundle(url: url)?.bundleIdentifier ?? "").hasPrefix("com.renicon.shortcut.")
    }

    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func shortcutURL(for entry: AppEntry) -> URL {
        folder.appendingPathComponent(sanitize(entry.displayName) + ".app", isDirectory: true)
    }

    @discardableResult
    static func build(for entry: AppEntry, icon: NSImage) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let app = shortcutURL(for: entry)
        // Remove a versão anterior (inclusive se o nome mudou).
        var renamedFrom: String?
        if let old = entry.shortcutPath, old != app.path, fm.fileExists(atPath: old) {
            try? Shell.run(lsregister, ["-u", old])
            try fm.removeItem(atPath: old)
            renamedFrom = old
        }
        if fm.fileExists(atPath: app.path) {
            // Nunca apaga um app de verdade que tenha o mesmo nome.
            guard isOurShortcut(app) else {
                throw NSError(domain: "Renicon", code: 5, userInfo: [NSLocalizedDescriptionKey:
                    "Já existe um app chamado “\(entry.displayName)” em \(folder.path). Escolha outro nome."])
            }
            try fm.removeItem(at: app)
        }

        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // Info.plist
        let plist: [String: Any] = [
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "com.renicon.shortcut.\(entry.id.uuidString.lowercased())",
            "CFBundleName": entry.displayName,
            "CFBundleDisplayName": entry.displayName,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "RENOriginalBundleIdentifier": entry.bundleIdentifier ?? "",
            "RENOriginalPath": entry.originalPath,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try "APPL????".write(to: contents.appendingPathComponent("PkgInfo"), atomically: true, encoding: .utf8)

        // Executável: abre o app original repassando argumentos/arquivos.
        let launcher = macOS.appendingPathComponent("launcher")
        try launcherScript(for: entry).write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        // Ícone
        // `icon` já vem estilizado pelo LibraryStore.
        try IconRenderer.writeICNS(from: icon, style: .original,
                                   to: resources.appendingPathComponent("AppIcon.icns"))

        // Assinatura ad-hoc, registro no LaunchServices e indexação no Spotlight.
        try? Shell.run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app.path])
        _ = try? Shell.run(lsregister, ["-f", "-R", "-trusted", app.path])
        _ = try? Shell.run("/usr/bin/mdimport", ["-i", app.path])
        _ = try? Shell.run("/usr/bin/touch", [app.path])
        NSWorkspace.shared.noteFileSystemChanged(app.path)
        if let renamedFrom {
            DockManager.replace(path: renamedFrom, with: app.path, label: entry.displayName)
        }
        return app
    }

    static func remove(_ entry: AppEntry) {
        guard let path = entry.shortcutPath, FileManager.default.fileExists(atPath: path) else { return }
        try? Shell.run(lsregister, ["-u", path])
        try? FileManager.default.removeItem(atPath: path)
        DockManager.unpin(path)
    }

    private static func launcherScript(for entry: AppEntry) -> String {
        let script = launcherBody(for: entry)
        guard entry.applyIconToOriginal else { return script }
        // Antes de abrir, recoloca o ícone no app original se uma atualização o removeu.
        // A checagem em shell é instantânea; o script só roda quando o ícone sumiu.
        let reapply = """
        if [ ! -e \(shellQuote(entry.originalPath))/"$(printf 'Icon\\r')" ]; then
          /usr/bin/osascript -l JavaScript \(shellQuote(AutoReapply.scriptURL.path)) \(entry.id.uuidString) >/dev/null 2>&1
        fi

        """
        return script.replacingOccurrences(of: "#!/bin/sh\n", with: "#!/bin/sh\n" + reapply)
    }

    private static func launcherBody(for entry: AppEntry) -> String {
        let path = shellQuote(entry.originalPath)
        if let bundleID = entry.bundleIdentifier, !bundleID.isEmpty {
            return """
            #!/bin/sh
            # Gerado pelo Renicon. Abre o app pelo identificador; se falhar, usa o caminho.
            /usr/bin/open -b \(shellQuote(bundleID)) "$@" 2>/dev/null || /usr/bin/open -a \(path) "$@" 2>/dev/null || \
              /usr/bin/osascript -e 'display alert "O app original não foi encontrado" message "Abra o Renicon para verificar este atalho." as warning'

            """
        }
        return """
        #!/bin/sh
        # Gerado pelo Renicon.
        /usr/bin/open -a \(path) "$@" 2>/dev/null || \
          /usr/bin/osascript -e 'display alert "O app original não foi encontrado" message "Abra o Renicon para verificar este atalho." as warning'

        """
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Atalho" : cleaned
    }
}
