import Foundation

/// Edita os itens fixados no Dock (preferências com.apple.dock › persistent-apps).
enum DockManager {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "persistent-apps" as CFString

    private static func persistentApps() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
    }

    private static func save(_ apps: [[String: Any]]) {
        CFPreferencesSetAppValue(key, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        try? Shell.run("/usr/bin/killall", ["Dock"])
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String else { return nil }
        if let url = URL(string: string), url.isFileURL { return normalize(url.path) }
        return normalize(string)
    }

    private static func normalize(_ path: String) -> String {
        (path as NSString).standardizingPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func tile(for appPath: String, label: String) -> [String: Any] {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": label,
                "file-type": 41,
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: appPath).absoluteString,
                    "_CFURLStringType": 15,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    static func contains(_ appPath: String) -> Bool {
        persistentApps().contains { path(of: $0) == normalize(appPath) }
    }

    /// Fixa o atalho no Dock. Se o app original estiver fixado, o atalho ocupa o lugar dele.
    static func pin(shortcut: String, replacing original: String?, label: String) {
        var apps = persistentApps()
        if apps.contains(where: { path(of: $0) == normalize(shortcut) }) { return }
        let newTile = tile(for: shortcut, label: label)
        if let original, let index = apps.firstIndex(where: { path(of: $0) == normalize(original) }) {
            apps[index] = newTile
        } else {
            apps.append(newTile)
        }
        save(apps)
    }

    /// Quando o atalho é renomeado, o item fixado passa a apontar para o novo caminho.
    static func replace(path old: String, with new: String, label: String) {
        var apps = persistentApps()
        guard let index = apps.firstIndex(where: { path(of: $0) == normalize(old) }) else { return }
        apps[index] = tile(for: new, label: label)
        save(apps)
    }

    static func unpin(_ appPath: String) {
        var apps = persistentApps()
        let before = apps.count
        apps.removeAll { path(of: $0) == normalize(appPath) }
        if apps.count != before { save(apps) }
    }
}
