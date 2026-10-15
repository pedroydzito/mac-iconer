import RenCore
import AppKit

/// Busca ícones do mesmo app na App Store (Mac e iPhone/iPad), como o IconSur faz.
/// Usa a API pública de busca do iTunes, que não precisa de conta nem chave.
enum IconSuggestions {
    enum Source: String, Hashable {
        case appStoreMac, appStoreiOS, whiteSur, recent

        var label: String {
            switch self {
            case .appStoreMac: return "App Store (Mac)"
            case .appStoreiOS: return "App Store (iPhone/iPad)"
            case .whiteSur: return "WhiteSur"
            case .recent: return "Usado recentemente"
            }
        }
    }

    struct Suggestion: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
        let source: Source
        /// Ícones do iPhone/iPad são quadrados e recebem o formato macOS; os demais já vêm prontos.
        var isMac: Bool { source != .appStoreiOS }
    }

    static func search(for entry: AppEntry) async -> [Suggestion] {
        // 1) O próprio app na Mac App Store, pelo identificador exato.
        var exact: [Suggestion] = []
        if let id = entry.bundleIdentifier {
            exact = await query("https://itunes.apple.com/lookup?bundleId=\(encode(id))&entity=macSoftware", isMac: true)
        }
        // 2) Buscas por nome, mas só ficam resultados que tenham o nome do app de verdade.
        let key = keyword(for: entry)
        let term = encode(cleanName(entry.originalName))
        var byName = await WhiteSur.suggestions(for: entry)
        byName += await query("https://itunes.apple.com/search?term=\(term)&entity=macSoftware&limit=15", isMac: true)
        byName += await query("https://itunes.apple.com/search?term=\(term)&entity=software&limit=15", isMac: false)
        let relevant = byName.filter { suggestion in
            guard let key else { return false }
            return normalize(suggestion.name).contains(key)
        }
        var seen = Set<URL>()
        return (exact + relevant).filter { seen.insert($0.url).inserted }.prefix(5).map { $0 }
    }

    /// "Adobe Photoshop 2026" → "Adobe Photoshop".
    private static func cleanName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*(19|20)\d\d\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+v?\d+(\.\d+)*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    /// A palavra que identifica o app (ignora marcas genéricas): "Adobe Photoshop 2026" → "photoshop".
    private static func keyword(for entry: AppEntry) -> String? {
        let generic: Set<String> = ["adobe", "microsoft", "google", "apple", "the", "app", "for", "mac", "macos", "pro", "studio", "and"]
        let words = cleanName(entry.originalName).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let candidates = words.filter { !generic.contains($0) && $0.count >= 3 }
        return (candidates.max(by: { $0.count < $1.count }) ?? words.first).map(normalize)
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func query(_ string: String, isMac: Bool) async -> [Suggestion] {
        guard let url = URL(string: string),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["results"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let art = (item["artworkUrl512"] ?? item["artworkUrl100"]) as? String,
                  // Pede a versão de 1024 px do mesmo ícone.
                  let big = URL(string: art.replacingOccurrences(of: "512x512bb", with: "1024x1024bb")
                                        .replacingOccurrences(of: "100x100bb", with: "1024x1024bb")) else { return nil }
            let name = item["trackName"] as? String ?? ""
            // A WhiteSur entra com o nome do arquivo ("WhiteSur: photoshop").
            return Suggestion(id: big.absoluteString, name: name, url: big, source: isMac ? .appStoreMac : .appStoreiOS)
        }
    }

    static func download(_ suggestion: Suggestion) async -> NSImage? {
        await loadImage(suggestion.url)
    }

    /// Carrega PNG, ICNS ou SVG, de arquivo ou da internet (com cache em memória).
    static func loadImage(_ url: URL) async -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let image = NSImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    private static let imageCache = NSCache<NSURL, NSImage>()
}

/// Ícones do pacote WhiteSur (github.com/vinceliuice/WhiteSur-icon-theme, GPL-3.0),
/// no estilo do macOS. A lista de nomes é baixada uma vez e guardada por 7 dias.
enum WhiteSur {
    private static let repo = "vinceliuice/WhiteSur-icon-theme"
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renicon/whitesur-index.json")
    }

    static func suggestions(for entry: AppEntry) async -> [IconSuggestions.Suggestion] {
        let names = await index()
        guard !names.isEmpty else { return [] }
        let terms = searchTerms(for: entry)
        var scored: [(String, Int)] = []
        for name in names {
            if let rank = terms.firstIndex(of: name) {
                scored.append((name, rank))
            } else if let rank = terms.firstIndex(where: { $0.count >= 4 && name.hasPrefix($0) }) {
                scored.append((name, 100 + rank))
            }
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(4).compactMap { name, _ in
            guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/master/src/apps/scalable/\(name).svg")
            else { return nil }
            return IconSuggestions.Suggestion(id: url.absoluteString, name: "WhiteSur: \(name)", url: url, source: .whiteSur)
        }
    }

    /// Nomes possíveis no padrão do Linux: "adobe-photoshop", "photoshop", "com.adobe.photoshop"…
    private static func searchTerms(for entry: AppEntry) -> [String] {
        func slug(_ s: String) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        let name = slug(entry.originalName)
        let withoutYear = name.replacingOccurrences(of: #"-(19|20)\d\d$"#, with: "", options: .regularExpression)
        var terms = [name, withoutYear]
        let words = withoutYear.split(separator: "-").map(String.init)
        if words.count > 1 { terms.append(words.dropFirst().joined(separator: "-")); terms.append(words.last!) }
        if let id = entry.bundleIdentifier?.lowercased() {
            terms.append(id)
            if let last = id.split(separator: ".").last { terms.append(String(last)) }
        }
        var seen = Set<String>()
        return terms.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static var memory: [String]?

    private static func index() async -> [String] {
        if let memory { return memory }
        let fm = FileManager.default
        if let date = (try? fm.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 7 * 24 * 3600,
           let data = try? Data(contentsOf: cacheURL),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            memory = names
            return names
        }
        // Lista os arquivos de src/apps/scalable (ignora links simbólicos).
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/git/trees/master:src/apps/scalable"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else { return [] }
        let names = tree.compactMap { item -> String? in
            guard item["mode"] as? String != "120000", let path = item["path"] as? String,
                  path.hasSuffix(".svg") else { return nil }
            return String(path.dropLast(4))
        }
        try? fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(names).write(to: cacheURL)
        memory = names
        return names
    }
}

extension IconRenderer {
    /// Uma imagem com cantos transparentes já tem formato de ícone; senão, precisa do formato macOS.
    static func suggestedStyle(for image: NSImage) -> IconStyle {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = Optional(NSBitmapImageRep(cgImage: cg)) else { return .macOS }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 4, h > 4 else { return .macOS }
        let corners = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]
        let transparent = corners.allSatisfy { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 1) < 0.1 }
        return transparent ? .original : .macOS
    }
}
