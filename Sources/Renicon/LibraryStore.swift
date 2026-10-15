import RenCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published var entries: [AppEntry] = [] { didSet { save() } }
    @Published var selection: AppEntry.ID?
    @Published var errorMessage: String?
    /// Aviso curto e discreto (ex.: "Aplicado").
    @Published var toast: String?
    /// O macOS bloqueou a troca do ícone no app original: falta a permissão "Gerenciamento de Apps".
    @Published var needsAppManagement = false
    @Published var loadingSuggestions: Set<AppEntry.ID> = []
    @Published var busy = false
    /// Desfazer/refazer (⌘Z / ⇧⌘Z) da janela principal.
    var undoManager: UndoManager?

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
        migrate()
    }

    /// Ajustes únicos para bibliotecas criadas em versões anteriores.
    private func migrate() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "migratedApplyToOriginal") {
            // Antes da 1.3 a opção vinha desligada; apps com ícone passam a usá-la no app aberto.
            for i in entries.indices where entries[i].hasCustomIcon && !entries[i].applyIconToOriginal {
                entries[i].applyIconToOriginal = true
                entries[i].hasPendingChanges = true
            }
            defaults.set(true, forKey: "migratedApplyToOriginal")
        }
        // Desfaz renomeações de apps originais feitas pelas versões 1.6–1.8.
        var restored: [(UUID, Bool)] = []
        for i in entries.indices where entries[i].renameOriginal {
            let wasInDock = restoreRenamedOriginal(&entries[i])
            restored.append((entries[i].id, wasInDock))
        }
        defaults.removeObject(forKey: "dockMode")
        if !restored.isEmpty {
            Task { @MainActor in
                for (id, wasInDock) in restored {
                    await self.apply(id)
                    if wasInDock { await self.pinToDock(id) }
                }
                self.showToast("Apps originais voltaram ao nome de sempre")
            }
        }
        if !defaults.bool(forKey: "cleanedDuplicateShortcuts") {
            let paths = entries.compactMap(\.shortcutPath)
            Task.detached { ShortcutBuilder.cleanUpDuplicateRegistrations(paths) }
            defaults.set(true, forKey: "cleanedDuplicateShortcuts")
        }
        if !defaults.bool(forKey: "migratedCompiledLauncher") {
            // Atalhos antigos usavam um script como executável e não apareciam no Spotlight.
            for i in entries.indices where entries[i].lastApplied != nil {
                entries[i].hasPendingChanges = true
            }
            defaults.set(true, forKey: "migratedCompiledLauncher")
        }
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
        for file in files where !file.hasDirectoryPath && !ids.contains(String(file.deletingPathExtension().lastPathComponent.prefix(36))) {
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
        // O LaunchServices pode lembrar de um app já apagado: confere se o arquivo existe.
        if let id = entry.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           fm.fileExists(atPath: url.path) {
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

    func showToast(_ message: String) {
        toast = message
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        let current = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == current { self?.toast = nil }
        }
    }

    /// Outro app da lista com o mesmo nome (o atalho de um sobrescreveria o do outro).
    func duplicate(of entry: AppEntry) -> AppEntry? {
        let name = ShortcutBuilder.sanitize(entry.displayName).lowercased()
        return entries.first { $0.id != entry.id && ShortcutBuilder.sanitize($0.displayName).lowercased() == name }
    }

    /// Seleciona o app anterior/seguinte da faixa.
    func selectAdjacent(_ step: Int) {
        guard !entries.isEmpty else { return }
        let index = selection.flatMap { id in entries.firstIndex { $0.id == id } } ?? (step > 0 ? -1 : entries.count)
        selection = entries[(index + step + entries.count) % entries.count].id
    }

    /// Ao voltar para o Iconer: relê os ícones originais (um app pode ter sido atualizado).
    func refreshAfterActivation() {
        originalIconCache.removeAll()
        removeUninstalledApps()
        objectWillChange.send()
    }

    // MARK: - Desfazer

    /// Troca o estado editável de um app registrando o desfazer (nome, formato, ajustes e ícone).
    func update(_ id: AppEntry.ID, actionName: String, _ change: (inout AppEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = entries[i]
        let iconBefore = before.hasCustomIcon ? (try? Data(contentsOf: customIconURL(for: before))) : nil
        var after = before
        change(&after)
        guard after != before else { return }
        after.hasPendingChanges = true
        entries[i] = after
        registerUndo(id: id, restoring: before, iconData: iconBefore, actionName: actionName)
    }

    /// Registra um desfazer que volta o app para `snapshot` (inclusive a imagem do ícone).
    func registerUndo(id: AppEntry.ID, restoring snapshot: AppEntry, iconData: Data?, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.performUndo(id: id, restoring: snapshot, iconData: iconData, actionName: actionName) }
        }
        undoManager.setActionName(actionName)
    }

    private func performUndo(id: AppEntry.ID, restoring snapshot: AppEntry, iconData: Data?, actionName: String) {
        let store = self
        do {
            guard let i = store.entries.firstIndex(where: { $0.id == id }) else { return }
            let current = store.entries[i]
            let currentIcon = current.hasCustomIcon ? (try? Data(contentsOf: store.customIconURL(for: current))) : nil
            if let iconData { try? iconData.write(to: store.customIconURL(for: snapshot), options: .atomic) }
            store.clearStyledCache(for: id)
            var restored = snapshot
            restored.shortcutPath = current.shortcutPath
            restored.lastApplied = current.lastApplied
            restored.hasPendingChanges = true
            store.entries[i] = restored
            // Registra o inverso para o ⇧⌘Z (refazer).
            store.registerUndo(id: id, restoring: current, iconData: currentIcon, actionName: actionName)
        }
    }

    // MARK: - Edição

    func add(urls: [URL]) {
        var lastID: UUID?
        for url in urls where url.pathExtension.lowercased() == "app" {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            if let existing = entries.first(where: { ($0.bundleIdentifier != nil && $0.bundleIdentifier == bundleID) || $0.originalPath == url.path }) {
                lastID = existing.id
                showToast("“\(existing.displayName)” já estava na lista")
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

    func setCustomIcon(_ image: NSImage, for id: AppEntry.ID, style: IconStyle? = nil) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        guard let data = IconRenderer.pngData(for: image, size: 1024, style: .original) else {
            errorMessage = "Não foi possível ler essa imagem."
            return
        }
        do {
            let before = entries[i]
            let iconBefore = before.hasCustomIcon ? (try? Data(contentsOf: customIconURL(for: before))) : nil
            try data.write(to: customIconURL(for: entries[i]), options: .atomic)
            clearStyledCache(for: id)
            if !entries[i].hasCustomIcon {
                // Primeiro ícone escolhido: usa também no app original, para o Dock e o ⌘Tab.
                entries[i].applyIconToOriginal = true
            }
            entries[i].hasCustomIcon = true
            entries[i].iconStyle = style ?? IconRenderer.suggestedStyle(for: image)
            entries[i].hasPendingChanges = true
            registerUndo(id: id, restoring: before, iconData: iconBefore, actionName: "Trocar Ícone")
            saveRecent(data)
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
        panel.allowedContentTypes = [.image, .icns, .svg, .application]
        if panel.runModal() == .OK, let url = panel.url { setCustomIcon(from: url, for: id) }
    }

    func resetIcon(for id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = entries[i]
        let iconBefore = try? Data(contentsOf: customIconURL(for: before))
        registerUndo(id: id, restoring: before, iconData: iconBefore, actionName: "Restaurar Ícone")
        // O arquivo é mantido até o app ser removido, para o desfazer funcionar.
        clearStyledCache(for: id)
        entries[i].hasCustomIcon = false
        entries[i].hasPendingChanges = true
    }

    func clearStyledCache(for id: UUID) {
        styledIconCache = styledIconCache.filter { !$0.key.hasPrefix(id.uuidString) }
    }

    // MARK: - Aplicar

    /// Cria/atualiza o atalho. O trabalho pesado (ícones, assinatura) roda fora da
    /// thread principal para a interface não travar.
    @discardableResult
    func apply(_ id: AppEntry.ID) async -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        var entry = entries[i]
        if let other = duplicate(of: entry) {
            errorMessage = "Já existe um app chamado “\(other.displayName)” no Iconer. Escolha outro nome."
            return false
        }
        busy = true
        defer { busy = false }
        let firstApply = entry.lastApplied == nil
        let originalWasInDock = resolvedOriginalURL(for: entry).map { DockManager.contains($0.path) } ?? false
        if let current = resolvedOriginalURL(for: entry) { entry.originalPath = current.path }
        do {
            // O app original nunca é renomeado nem movido: instaladores e atualizadores
            // (ex.: Creative Cloud) precisam encontrá-lo exatamente onde está.
            let icon = effectiveIcon(for: entry)
            let snapshot = entry
            let url: URL? = try await Task.detached(priority: .userInitiated) {
                try ShortcutBuilder.build(for: snapshot, icon: icon)
            }.value
            guard let j = entries.firstIndex(where: { $0.id == id }) else { return false }
            // Mantém edições feitas enquanto aplicava; só marca como aplicado se nada mudou.
            var current = entries[j]
            current.shortcutPath = url?.path
            current.originalPath = entry.originalPath
            current.lastApplied = Date()
            let unchanged = current.customName == snapshot.customName && current.iconStyle == snapshot.iconStyle
                && current.adjustments == snapshot.adjustments && current.hasCustomIcon == snapshot.hasCustomIcon
                && current.applyIconToOriginal == snapshot.applyIconToOriginal
            current.hasPendingChanges = !unchanged
            entries[j] = current
            updateAutoReapply()
            do {
                try applyToOriginalIfNeeded(current, force: true)
            } catch {
                // O atalho foi criado; só o ícone do app original precisa de permissão.
                needsAppManagement = true
            }
            if let path = url?.path, DockManager.contains(path) {
                // O atalho já está no Dock: atualiza a etiqueta com o nome novo.
                let label = current.displayName
                let changed = await Task.detached { DockManager.relabel(path, label: label) }.value
                if !changed { reloadDock() }
            }
            showToast("“\(current.displayName)” aplicado")
            if firstApply && originalWasInDock {
                // O app já estava no Dock: troca pelo ajustado sem precisar clicar em nada.
                busy = false
                await pinToDock(id)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Ícones recentes

    private var recentURL: URL { iconsURL.appendingPathComponent("Recent", isDirectory: true) }

    /// Guarda uma cópia do ícone escolhido para reaproveitar em outros apps (até 12).
    private func saveRecent(_ data: Data) {
        try? fm.createDirectory(at: recentURL, withIntermediateDirectories: true)
        let files = recentFiles()
        if files.contains(where: { (try? Data(contentsOf: $0)) == data }) { return }
        try? data.write(to: recentURL.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000)).png"))
        for old in recentFiles().dropFirst(12) { try? fm.removeItem(at: old) }
        objectWillChange.send()
    }

    private func recentFiles() -> [URL] {
        let files = (try? fm.contentsOfDirectory(at: recentURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var recentIcons: [IconSuggestions.Suggestion] {
        recentFiles().map { IconSuggestions.Suggestion(id: $0.path, name: "Usado recentemente", url: $0, source: .recent) }
    }

    func clearRecents() {
        try? fm.removeItem(at: recentURL)
        objectWillChange.send()
    }

    // MARK: - Sugestões de ícone

    @Published var suggestions: [AppEntry.ID: [IconSuggestions.Suggestion]] = [:]

    func loadSuggestions(for id: AppEntry.ID) async {
        guard suggestions[id] == nil, let entry = entries.first(where: { $0.id == id }) else { return }
        suggestions[id] = []
        loadingSuggestions.insert(id)
        defer { loadingSuggestions.remove(id) }
        suggestions[id] = await IconSuggestions.search(for: entry)
    }

    func useSuggestion(_ suggestion: IconSuggestions.Suggestion, for id: AppEntry.ID) async {
        guard let image = await IconSuggestions.download(suggestion) else {
            errorMessage = "Não foi possível baixar esse ícone."
            return
        }
        let style: IconStyle
        switch suggestion.source {
        case .appStoreiOS: style = .macOS
        default: style = IconRenderer.suggestedStyle(for: image)
        }
        setCustomIcon(image, for: id, style: style)
    }

    /// Versões 1.6–1.8 podiam renomear o arquivo do app original. Isso confunde instaladores
    /// (o app "some" e pedem para reinstalar), então devolvemos o nome original.
    /// Retorna se o app estava fixado no Dock.
    @discardableResult
    private func restoreRenamedOriginal(_ entry: inout AppEntry) -> Bool {
        let renamed = URL(fileURLWithPath: entry.originalPath)
        let original = renamed.deletingLastPathComponent()
            .appendingPathComponent(ShortcutBuilder.sanitize(entry.originalName) + ".app", isDirectory: true)
        entry.renameOriginal = false
        entry.hasPendingChanges = true
        guard renamed.path != original.path, fm.fileExists(atPath: renamed.path) else {
            if fm.fileExists(atPath: original.path) { entry.originalPath = original.path }
            return false
        }
        let wasInDock = DockManager.contains(renamed.path)
        if fm.fileExists(atPath: original.path) {
            // O instalador já reinstalou o app com o nome original: a cópia renomeada é antiga.
            if (try? fm.trashItem(at: renamed, resultingItemURL: nil)) == nil {
                runAsAdmin("/bin/mv \(shellQuoted(renamed.path)) \(shellQuoted(NSHomeDirectory() + "/.Trash/"))")
            }
        } else if (try? fm.moveItem(at: renamed, to: original)) == nil {
            runAsAdmin("/bin/mv \(shellQuoted(renamed.path)) \(shellQuoted(original.path))")
        }
        _ = try? Shell.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", original.path])
        NSWorkspace.shared.noteFileSystemChanged(original.deletingLastPathComponent().path)
        entry.originalPath = original.path
        originalIconCache[entry.id] = nil
        return wasInDock
    }

    private func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Executa um comando pedindo a senha do Mac (só para desfazer renomeações antigas).
    private func runAsAdmin(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var errorInfo: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&errorInfo)
    }

    func applyAll() async {
        for id in entries.map(\.id) { await apply(id) }
    }

    /// Abre Ajustes do Sistema › Privacidade e Segurança › Gerenciamento de Apps.
    func openAppManagementSettings() {
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// O app usa um ícone de catálogo (Assets.car): com ele aberto, o Dock pode mostrar o ícone dele.
    func drawsOwnIcon(_ entry: AppEntry) -> Bool {
        guard let url = resolvedOriginalURL(for: entry), let bundle = Bundle(url: url) else { return false }
        return bundle.object(forInfoDictionaryKey: "CFBundleIconName") != nil
            && bundle.object(forInfoDictionaryKey: "CFBundleIconFile") == nil
    }

    /// Desfaz tudo (atalhos, ícones, Dock, ajudante) e move o Iconer para o Lixo.
    func uninstall() {
        removeAll()
        DockHelperInstaller.uninstall()
        try? fm.removeItem(at: supportURL)
        try? fm.removeItem(at: ShortcutBuilder.legacyFolder)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.renicon.app")
        try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
    }

    /// Remove todos os atalhos, devolve os ícones originais e apaga a regra do launchd.
    func removeAll() {
        for id in entries.map(\.id) { remove(id) }
        AutoReapply.update([])
    }

    func remove(_ id: AppEntry.ID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[i]
        ShortcutBuilder.remove(entry)
        if entry.renameOriginal { restoreRenamedOriginal(&entry) }
        // Se o app original continua no Dock, devolve a etiqueta original.
        if let original = resolvedOriginalURL(for: entry)?.path {
            let label = entry.originalName
            Task.detached { DockManager.relabel(original, label: label) }
        }
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
                "Sem permissão para alterar o ícone de \(entry.originalName). O atalho foi criado normalmente; dê ao Iconer “Acesso Total ao Disco” ou “Gerenciamento de Apps” em Ajustes do Sistema > Privacidade e Segurança."])
        }
    }

    /// O que vai para o Dock: com o ícone aplicado ao original, o próprio app original
    /// (assim o app aberto usa o mesmo item do Dock, sem aparecer duplicado); senão, o atalho.
    private func dockTarget(for entry: AppEntry) -> String? {
        return entry.shortcutPath
    }

    func isInDock(_ entry: AppEntry) -> Bool {
        if isRunning(entry), let original = resolvedOriginalURL(for: entry)?.path, DockManager.contains(original) { return true }
        guard let target = dockTarget(for: entry), DockManager.contains(target) else { return false }
        // Se o atalho também está fixado junto do original, ainda há o que arrumar.
        if target != entry.shortcutPath, let shortcut = entry.shortcutPath, DockManager.contains(shortcut) { return false }
        return true
    }

    /// Fixa no Dock fora da thread principal (o Dock é reiniciado e conferido).
    @discardableResult
    func pinToDock(_ id: AppEntry.ID) async -> Bool {
        guard let entry = entries.first(where: { $0.id == id }), let target = dockTarget(for: entry) else { return false }
        let others = [entry.shortcutPath, resolvedOriginalURL(for: entry)?.path].compactMap { $0 }
        let label = entry.displayName
        busy = true
        defer { busy = false }
        await Task.detached { DockManager.pin(target, replacing: others, label: label) }.value
        objectWillChange.send()
        // Se o app estiver aberto agora, o ajudante põe o app no lugar do atalho.
        updateDockHelper()
        let pinned = DockManager.contains(target)
        if !pinned { errorMessage = "O Dock não aceitou a mudança. Tente de novo em alguns segundos." }
        return pinned
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

    /// Prepara o script e a regra do launchd que mantêm os ícones sem o Iconer aberto.
    func updateAutoReapply() {
        var items: [AutoReapply.Item] = []
        for entry in entries where entry.lastApplied != nil {
            var iconPath: String?
            if entry.applyIconToOriginal, let custom = customIcon(for: entry),
               let data = IconRenderer.pngData(for: custom, size: 1024, style: entry.iconStyle, adjustments: entry.adjustments) {
                let url = styledIconURL(for: entry)
                try? data.write(to: url, options: .atomic)
                iconPath = url.path
            }

            let path = resolvedOriginalURL(for: entry)?.path ?? entry.originalPath
            items.append(.init(id: entry.id.uuidString, bundleID: entry.bundleIdentifier, path: path, icon: iconPath, name: nil,
                               shortcut: entry.shortcutPath))
        }
        AutoReapply.update(items)
        updateDockHelper()
    }

    /// Lista para o ajudante do Dock: atalho fechado ⇄ app aberto, sempre na mesma posição.
    func updateDockHelper() {
        let items: [DockSwapItem] = entries.compactMap { entry in
            guard entry.lastApplied != nil, let shortcut = entry.shortcutPath,
                  let bundleID = entry.bundleIdentifier else { return nil }
            let original = resolvedOriginalURL(for: entry)?.path ?? entry.originalPath
            return DockSwapItem(bundleID: bundleID, shortcut: shortcut, original: original,
                                originalLabel: entry.originalName, shortcutLabel: entry.displayName)
        }
        DockHelperInstaller.update(items)
    }

    /// Está no Dock: o atalho, ou o próprio app enquanto ele está aberto (trocado pelo ajudante).
    private func isRunning(_ entry: AppEntry) -> Bool {
        guard let id = entry.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }


    /// Verifica todos os apps: segue apps movidos, recria atalhos apagados e
    /// reaplica ícones que foram perdidos em uma atualização.
    /// Apps desinstalados saem do Iconer (atalho, Dock, Spotlight e cópias de ícone).
    func removeUninstalledApps() {
        let gone = entries.filter { resolvedOriginalURL(for: $0) == nil && !fm.fileExists(atPath: $0.originalPath) }
        guard !gone.isEmpty else { return }
        for entry in gone { remove(entry.id) }
        showToast(gone.count == 1
                  ? "“\(gone[0].displayName)” foi desinstalado e saiu do Iconer"
                  : "\(gone.count) apps desinstalados saíram do Iconer")
    }

    func sync() {
        removeUninstalledApps()
        for i in entries.indices {
            var entry = entries[i]
            guard entry.lastApplied != nil else { continue }
            var needsRebuild = false
            if let current = resolvedOriginalURL(for: entry), current.path != entry.originalPath {
                entry.originalPath = current.path
                needsRebuild = true
            }
            if let path = entry.shortcutPath,
               !fm.fileExists(atPath: path) || path.hasPrefix(ShortcutBuilder.legacyFolder.path + "/") {
                needsRebuild = true
            }
            if needsRebuild, let url = try? ShortcutBuilder.build(for: entry, icon: effectiveIcon(for: entry)) {
                entry.shortcutPath = url.path
            }
            try? applyToOriginalIfNeeded(entry, force: false)
            if entry != entries[i] { entries[i] = entry }
        }
        updateAutoReapply()
        // Remove a pasta antiga (~/Applications/Renicon) quando ficar vazia.
        let legacy = ShortcutBuilder.legacyFolder.path
        if (try? fm.contentsOfDirectory(atPath: legacy).filter { $0 != ".DS_Store" }.isEmpty) == true {
            try? fm.removeItem(atPath: legacy)
        }
    }
}
