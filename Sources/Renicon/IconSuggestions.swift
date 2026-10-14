import AppKit

/// Busca ícones do mesmo app na App Store (Mac e iPhone/iPad), como o IconSur faz.
/// Usa a API pública de busca do iTunes, que não precisa de conta nem chave.
enum IconSuggestions {
    struct Suggestion: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
        /// Ícones do Mac já vêm no formato certo; os do iPhone são quadrados e recebem o formato macOS.
        let isMac: Bool
    }

    static func search(for entry: AppEntry) async -> [Suggestion] {
        var results: [Suggestion] = []
        if let id = entry.bundleIdentifier {
            results += await query("https://itunes.apple.com/lookup?bundleId=\(encode(id))&entity=macSoftware", isMac: true)
        }
        let term = encode(entry.originalName)
        results += await query("https://itunes.apple.com/search?term=\(term)&entity=macSoftware&limit=6", isMac: true)
        results += await query("https://itunes.apple.com/search?term=\(term)&entity=software&limit=6", isMac: false)
        var seen = Set<URL>()
        return results.filter { seen.insert($0.url).inserted }.prefix(10).map { $0 }
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
            return Suggestion(id: big.absoluteString, name: name, url: big, isMac: isMac)
        }
    }

    static func download(_ suggestion: Suggestion) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: suggestion.url) else { return nil }
        return NSImage(data: data)
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
