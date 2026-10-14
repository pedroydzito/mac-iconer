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
    /// Ícones já estilizados, para não renderizar de novo a cada atualização da tela.
    private var styledIconCache: [String: NSImage] = [:]

    init() {
        supportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renicon", isDirectory: true)
        try? fm.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: databaseURL),
           let decoded = try? Self.decoder.decode([AppEntry].self, from: data) {
            entries = decoded
        }
        removeOrphanIcons()
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Apaga cópias de imagens que não pertencem a nenhum app da lista.
    private func removeOrphanIcons() {
        let ids = Set(entries.filter(\.hasCustomIcon).map(\.id.uuidString))
        let files = (try? fm.contentsOfDirectory(at: iconsURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where !ids.contains(String(file.deletingPathExtension().lastPathComponent.prefix(36))) {
            try? fm.removeItem(at: file)
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
            get: { self.entries.first(where: { $0.id == id }) ?? AppEntry(originalPath: "", bundleIdentifier: nil, originalName: "", customName: "") },
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
        let key = "\(entry.id.uuidString)-\(entry.iconStyle.rawValue)-\(entry.adjustments.zoom)-\(entry.adjustments.background)"
        if entry.hasCustomIcon, let cached = styledIconCache[key] { return cached }
        if let custom = customIcon(for: entry) {
            let styled = IconRenderer.styledImage(custom, style: entry.iconStyle, adjustments: entry.adjustments)
            clearStyledCache(for: entry.id)
            styledIconCache[key] = styled
            return styled
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
            clearStyledCache(for: id)
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

    /// Recebe o que foi arrastado para o ícone: arquivo de imagem, imagem vinda do
    /// navegador ou um app (que é adicionado à lista).
    func loadIcon(from providers: [NSItemProvider], for id: AppEntry.ID) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.pathExtension.lowercased() == "app" {
                        self.add(urls: [url])
                    } else {
                        self.setCustomIcon(from: url, for: id)
                    }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if let image = NSImage(data: data) {
                        self.setCustomIcon(image, for: id)
                    } else {
                        self.errorMessage = "Não foi possível ler essa imagem."
                    }
                }
            }
            return true
        }
        return false
    }

    func pasteIcon(for id: AppEntry.ID) {
        let pasteboard = NSPasteboard.general
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            setCustomIcon(from: url, for: id)
        } else if let image = NSImage(pasteboard: pasteboard) {
            setCustomIcon(image, for: id)
        } else {
            errorMessage = "Não há nenhuma imagem copiada."
        }
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
        clearStyledCache(for: id)
        entries[i].hasCustomIcon = false
        entries[i].hasPendingChanges = true
    }

    private func clearStyledCache(for id: UUID) {
        styledIconCache = styledIconCache.filter { !$0.key.hasPrefix(id.uuidString) }
    }

    // MARK: - Aplicar

    /// Cria/atualiza o atalho. O trabalho pesado (ícones, assinatura) roda fora da
    /// thread principal para a interface não travar.
    @discardableResult
    func apply(_ id: AppEntry.ID) async -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        var entry = entries[i]
        let name = ShortcutBuilder.sanitize(entry.displayName).lowercased()
        if let other = entries.first(where: { $0.id != id && ShortcutBuilder.sanitize($0.displayName).lowercased() == name }) {
            errorMessage = "Já existe um app chamado “\(other.displayName)” no Renicon. Escolha outro nome."
            return false
        }
        busy = true
        defer { busy = false }
        if let current = resolvedOriginalURL(for: entry) { entry.originalPath = current.path }
        let icon = effectiveIcon(for: entry)
        let snapshot = entry
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try ShortcutBuilder.build(for: snapshot, icon: icon)
            }.value
            guard let j = entries.firstIndex(where: { $0.id == id }) else { return false }
            // Mantém edições feitas enquanto aplicava; só marca como aplicado se nada mudou.
            var current = entries[j]
            current.shortcutPath = url.path
            current.originalPath = entry.originalPath
            current.lastApplied = Date()
            let unchanged = current.customName == snapshot.customName && current.iconStyle == snapshot.iconStyle
                && current.adjustments == snapshot.adjustments && current.hasCustomIcon == snapshot.hasCustomIcon
                && current.applyIconToOriginal == snapshot.applyIconToOriginal
            current.hasPendingChanges = !unchanged
            entries[j] = current
            updateAutoReapply()
            try applyToOriginalIfNeeded(current, force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyAll() async {
        for id in entries.map(\.id) { await apply(id) }
    }

    /// Remove todos os atalhos, devolve os ícones originais e apaga a regra do launchd.
    func removeAll() {
        for id in entries.map(\.id) { remove(id) }
        AutoReapply.update([])
    }

    func remove(_ id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[i]
        ShortcutBuilder.remove(entry)
        if entry.applyIconToOriginal, let url = resolvedOriginalURL(for: entry) {
            NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
        }
        try? fm.removeItem(at: customIconURL(for: entry))
        originalIconCache[id] = nil
        try? fm.removeItem(at: styledIconURL(for: entry))
        entries.remove(at: i)
        if selection == id { selection = entries.first?.id }
        updateAutoReapply()
    }

    func setApplyToOriginal(_ value: Bool, for id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        // Garante que o ícone original seja lembrado antes de alterá-lo.
        _ = originalIcon(for: entries[i])
        entries[i].applyIconToOriginal = value
        entries[i].hasPendingChanges = true
        if !value, let url = resolvedOriginalURL(for: entries[i]) {
            NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
            refreshIcon(at: url)
        }
        updateAutoReapply()
    }

    private func applyToOriginalIfNeeded(_ entry: AppEntry, force: Bool) throws {
        guard entry.applyIconToOriginal, let custom = customIcon(for: entry),
              let url = resolvedOriginalURL(for: entry) else { return }
        // Um ícone personalizado do Finder fica no arquivo "Icon\r" dentro do pacote.
        // Quando o app é atualizado, o pacote é substituído e esse arquivo some.
        let marker = url.appendingPathComponent("Icon\r").path
        if !force && fm.fileExists(atPath: marker) { return }
        let styled = IconRenderer.styledImage(custom, style: entry.iconStyle, adjustments: entry.adjustments, size: 1024)
        if NSWorkspace.shared.setIcon(styled, forFile: url.path, options: []) {
            refreshIcon(at: url)
        } else {
            throw NSError(domain: "Renicon", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Sem permissão para alterar o ícone de \(entry.originalName). O atalho foi criado normalmente; dê ao Renicon “Acesso Total ao Disco” ou “Gerenciamento de Apps” em Ajustes do Sistema > Privacidade e Segurança."])
        }
    }

    func isInDock(_ entry: AppEntry) -> Bool {
        entry.shortcutPath.map(DockManager.contains) ?? false
    }

    func pinToDock(_ id: AppEntry.ID) {
        guard let entry = entries.first(where: { $0.id == id }), let path = entry.shortcutPath else { return }
        DockManager.pin(shortcut: path, replacing: resolvedOriginalURL(for: entry)?.path, label: entry.displayName)
        objectWillChange.send()
    }

    /// Força o Finder/Dock a reler o ícone de um pacote.
    private func refreshIcon(at url: URL) {
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }

    /// Reinicia o Dock para que ele mostre os ícones novos imediatamente.
    func reloadDock() {
        try? Shell.run("/usr/bin/killall", ["Dock"])
    }

    // MARK: - Sincronização (após atualizações)

    private func styledIconURL(for entry: AppEntry) -> URL {
        iconsURL.appendingPathComponent("\(entry.id.uuidString)-styled.png")
    }

    /// Prepara o script e a regra do launchd que mantêm os ícones sem o Renicon aberto.
    func updateAutoReapply() {
        var items: [AutoReapply.Item] = []
        for entry in entries where entry.applyIconToOriginal && entry.lastApplied != nil {
            guard let custom = customIcon(for: entry),
                  let data = IconRenderer.pngData(for: custom, size: 1024, style: entry.iconStyle, adjustments: entry.adjustments) else { continue }
            let url = styledIconURL(for: entry)
            try? data.write(to: url, options: .atomic)
            let path = resolvedOriginalURL(for: entry)?.path ?? entry.originalPath
            items.append(.init(id: entry.id.uuidString, bundleID: entry.bundleIdentifier, path: path, icon: url.path))
        }
        AutoReapply.update(items)
    }


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
        updateAutoReapply()
    }
}
