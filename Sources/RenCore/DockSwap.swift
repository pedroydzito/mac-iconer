import Foundation

/// Combinado entre o Renicon e o ajudante do Dock (arquivo dock.json).
public struct DockSwapItem: Codable, Equatable {
    public let bundleID: String
    /// Atalho com o nome e o ícone personalizados.
    public let shortcut: String
    /// App original (caminho conhecido; o ajudante também procura pelo bundle ID).
    public let original: String
    public let originalLabel: String
    public let shortcutLabel: String

    public init(bundleID: String, shortcut: String, original: String, originalLabel: String, shortcutLabel: String) {
        self.bundleID = bundleID
        self.shortcut = shortcut
        self.original = original
        self.originalLabel = originalLabel
        self.shortcutLabel = shortcutLabel
    }
}

public enum DockSwap {
    public static let helperLabel = "com.renicon.dockhelper"
    /// Aviso que o Renicon manda para o ajudante reler o arquivo e conferir o Dock.
    public static let reloadNotification = Notification.Name("com.renicon.dockhelper.reload")

    public static var supportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Renicon", isDirectory: true)
    }
    public static var manifestURL: URL { supportURL.appendingPathComponent("dock.json") }

    public static func load() -> [DockSwapItem] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([DockSwapItem].self, from: data)) ?? []
    }

    public static func save(_ items: [DockSwapItem]) {
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: manifestURL, options: .atomic) }
    }

    /// A regra: app aberto → o próprio app no lugar do atalho; app fechado → o atalho.
    /// Calcula as trocas necessárias para o estado atual.
    public static func changes(for items: [DockSwapItem], running: Set<String>,
                               resolve: (DockSwapItem) -> String) -> [(old: String, new: String, label: String)] {
        var result: [(old: String, new: String, label: String)] = []
        for item in items {
            let original = resolve(item)
            if running.contains(item.bundleID) {
                if DockManager.contains(item.shortcut) {
                    result.append((old: item.shortcut, new: original, label: item.originalLabel))
                }
            } else if DockManager.contains(original) {
                result.append((old: original, new: item.shortcut, label: item.shortcutLabel))
            }
        }
        return result
    }
}
