import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published var entries: [AppEntry] = [] { didSet { save() } }
    @Published var selection: AppEntry.ID?
    @Published var errorMessage: String?
    @Published var busy = false

    private let fm = FileManager.default
    private let supportURL: URL
    private var iconsURL: URL { supportURL.appendingPathComponent("Icons", isDirectory: true) }
    private var databaseURL: URL { supportURL.appendingPathComponent("library.json") }
    /// Ícones originais guardados antes de aplicar o ícone personalizado ao app original.
    private var originalIconCache: [UUID: NSImage] = [:]

    init() {
        supportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renicon", isDirectory: true)
        try? fm.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: databaseURL),
           let decoded = try? JSONDecoder().decode([AppEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: databaseURL, options: .atomic)
        }
    }

    // MARK: - Consulta

    func binding(for id: AppEntry.ID) -> Binding<AppEntry>? {
        guard entries.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.entries.first(where: { $0.id == id }) ?? AppEntry(originalPath: "", originalName: "", customName: "") },
            set: { newValue in
                if let i = self.entries.firstIndex(where: { $0.id == id }) {
                    var value = newValue
                    if value != self.entries[i] { value.hasPendingChanges = true }
                    self.entries[i] = value
                }
            }
        )
    }

    /// Localiza o app original atual (segue o bundle identifier se o app foi movido/atualizado).
    func resolvedOriginalURL(for entry: AppEntry) -> URL? {
        if let id = entry.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url
        }
        return fm.fileExists(atPath: entry.originalPath) ? entry.originalURL : nil
    }

    func originalIcon(for entry: AppEntry) -> NSImage {
        if let cached = originalIconCache[entry.id] { return cached }
        let url = resolvedOriginalURL(for: entry) ?? entry.originalURL
        let icon: NSImage
        if entry.applyIconToOriginal, let bundle = Bundle(url: url), let pristine = Self.bundleIcon(of: bundle) {
            icon = pristine
        } else {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        icon.size = NSSize(width: 512, height: 512)
        originalIconCache[entry.id] = icon
        return icon
    }

    /// Lê o ícone embutido no pacote, ignorando um ícone personalizado do Finder.
    private static func bundleIcon(of bundle: Bundle) -> NSImage? {
        guard var name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else { return nil }
        if !name.hasSuffix(".icns") { name += ".icns" }
        guard let url = bundle.resourceURL?.appendingPathComponent(name) else { return nil }
        return NSImage(contentsOf: url)
    }

    func customIconURL(for entry: AppEntry) -> URL { iconsURL.appendingPathComponent("\(entry.id.uuidString).png") }

    func customIcon(for entry: AppEntry) -> NSImage? {
        guard entry.hasCustomIcon else { return nil }
        return NSImage(contentsOf: customIconURL(for: entry))
    }

    /// Ícone final (já estilizado) que o atalho vai usar.
    func effectiveIcon(for entry: AppEntry) -> NSImage {
        if let custom = customIcon(for: entry) {
            return IconRenderer.styledImage(custom, style: entry.iconStyle)
        }
        return originalIcon(for: entry)
    }

    // MARK: - Edição

    func add(urls: [URL]) {
        var lastID: UUID?
        for url in urls where url.pathExtension.lowercased() == "app" {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            if let existing = entries.first(where: { ($0.bundleIdentifier != nil && $0.bundleIdentifier == bundleID) || $0.originalPath == url.path }) {
                lastID = existing.id
                continue
            }
            if bundleID?.hasPrefix("com.renicon.") == true { continue }
            let fileName = url.deletingPathExtension().lastPathComponent
            let entry = AppEntry(originalPath: url.path, bundleIdentifier: bundleID,
                                 originalName: fileName, customName: fileName)
            entries.append(entry)
            lastID = entry.id
        }
        if let lastID { selection = lastID }
    }

    func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Escolha os apps para personalizar"
        panel.prompt = "Adicionar"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func setCustomIcon(_ image: NSImage, for id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        guard let data = IconRenderer.pngData(for: image, size: 1024, style: .original) else {
            errorMessage = "Não foi possível ler essa imagem."
            return
        }
        do {
            try data.write(to: customIconURL(for: entries[i]), options: .atomic)
            entries[i].hasCustomIcon = true
            entries[i].hasPendingChanges = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCustomIcon(from url: URL, for id: AppEntry.ID) {
        let image: NSImage?
        if url.pathExtension.lowercased() == "app" {
            image = NSWorkspace.shared.icon(forFile: url.path)
            image?.size = NSSize(width: 1024, height: 1024)
        } else {
            image = NSImage(contentsOf: url)
        }
        if let image { setCustomIcon(image, for: id) } else { errorMessage = "Esse arquivo não é uma imagem válida." }
    }

    func chooseIcon(for id: AppEntry.ID) {
        let panel = NSOpenPanel()
        panel.title = "Escolha uma imagem para o ícone"
        panel.prompt = "Usar imagem"
        panel.allowedContentTypes = [.image, .icns, .application]
        if panel.runModal() == .OK, let url = panel.url { setCustomIcon(from: url, for: id) }
    }

    func resetIcon(for id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        try? fm.removeItem(at: customIconURL(for: entries[i]))
        entries[i].hasCustomIcon = false
        entries[i].hasPendingChanges = true
    }

    // MARK: - Aplicar

    func apply(_ id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        busy = true
        defer { busy = false }
        var entry = entries[i]
        if let current = resolvedOriginalURL(for: entry) { entry.originalPath = current.path }
        do {
            let url = try ShortcutBuilder.build(for: entry, icon: effectiveIcon(for: entry))
            entry.shortcutPath = url.path
            entry.lastApplied = Date()
            entry.hasPendingChanges = false
            try applyToOriginalIfNeeded(entry, force: true)
            entries[i] = entry
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAll() { entries.map(\.id).forEach(apply) }

    func remove(_ id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[i]
        ShortcutBuilder.remove(entry)
        if entry.applyIconToOriginal, let url = resolvedOriginalURL(for: entry) {
            NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
        }
        try? fm.removeItem(at: customIconURL(for: entry))
        originalIconCache[id] = nil
        entries.remove(at: i)
        if selection == id { selection = entries.first?.id }
    }

    func setApplyToOriginal(_ value: Bool, for id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        // Garante que o ícone original seja lembrado antes de alterá-lo.
        _ = originalIcon(for: entries[i])
        entries[i].applyIconToOriginal = value
        entries[i].hasPendingChanges = true
        if !value, let url = resolvedOriginalURL(for: entries[i]) {
            NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
        }
    }

    private func applyToOriginalIfNeeded(_ entry: AppEntry, force: Bool) throws {
        guard entry.applyIconToOriginal, let custom = customIcon(for: entry),
              let url = resolvedOriginalURL(for: entry) else { return }
        // Um ícone personalizado do Finder fica no arquivo "Icon\r" dentro do pacote.
        // Quando o app é atualizado, o pacote é substituído e esse arquivo some.
        let marker = url.appendingPathComponent("Icon\r").path
        if !force && fm.fileExists(atPath: marker) { return }
        let styled = IconRenderer.styledImage(custom, style: entry.iconStyle, size: 1024)
        if !NSWorkspace.shared.setIcon(styled, forFile: url.path, options: []) {
            throw NSError(domain: "Renicon", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Sem permissão para alterar o ícone de \(entry.originalName). O atalho foi criado normalmente; dê ao Renicon “Acesso Total ao Disco” ou “Gerenciamento de Apps” em Ajustes do Sistema > Privacidade e Segurança."])
        }
    }

    // MARK: - Sincronização (após atualizações)

    /// Verifica todos os apps: segue apps movidos, recria atalhos apagados e
    /// reaplica ícones que foram perdidos em uma atualização.
    func sync() {
        for i in entries.indices {
            var entry = entries[i]
            guard entry.lastApplied != nil else { continue }
            var needsRebuild = false
            if let current = resolvedOriginalURL(for: entry), current.path != entry.originalPath {
                entry.originalPath = current.path
                needsRebuild = true
            }
            if let path = entry.shortcutPath, !fm.fileExists(atPath: path) { needsRebuild = true }
            if needsRebuild, let url = try? ShortcutBuilder.build(for: entry, icon: effectiveIcon(for: entry)) {
                entry.shortcutPath = url.path
            }
            try? applyToOriginalIfNeeded(entry, force: false)
            if entry != entries[i] { entries[i] = entry }
        }
    }
}
