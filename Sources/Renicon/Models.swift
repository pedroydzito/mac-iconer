import AppKit

enum IconStyle: String, Codable, CaseIterable, Identifiable {
    /// Usa a imagem exatamente como foi escolhida.
    case original
    /// Recorta a imagem no formato "squircle" dos ícones do macOS, com margem e sombra.
    case macOS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Imagem original"
        case .macOS: return "Formato macOS"
        }
    }
}

/// Ajustes visuais do ícone no "Formato macOS".
struct IconAdjustments: Codable, Hashable {
    /// 1 = preenche o ícone; menor que 1 deixa margem; maior que 1 aproxima.
    var zoom: Double = 1
    /// Cor de fundo (hex "#RRGGBB"), visível em imagens com transparência.
    var background: String = "#FFFFFF"

    var backgroundColor: NSColor { NSColor(hex: background) ?? .white }
}

struct AppEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Caminho do app original quando foi adicionado (atualizado se o app mudar de lugar).
    var originalPath: String
    /// Identificador do app original. É ele que mantém o atalho funcionando após atualizações.
    var bundleIdentifier: String?
    var originalName: String
    var customName: String
    var hasCustomIcon = false
    var iconStyle: IconStyle = .macOS
    var adjustments = IconAdjustments()
    /// Também aplica o ícone ao app original (aparece no Dock enquanto o app está aberto).
    var applyIconToOriginal = false
    /// Renomeia o arquivo do app original (ex.: FilmCraft.app → Premiere Pro.app). Não mexe no
    /// conteúdo nem na assinatura; faz o nome ajustado aparecer no Dock/Finder com o app fechado.
    var renameOriginal = false
    /// Caminho do atalho gerado em ~/Applications.
    var shortcutPath: String?
    var lastApplied: Date?
    /// Há edições que ainda não foram aplicadas ao atalho.
    var hasPendingChanges = true

    var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? originalName : trimmed
    }

    var originalURL: URL { URL(fileURLWithPath: originalPath) }

    init(originalPath: String, bundleIdentifier: String?, originalName: String, customName: String) {
        self.originalPath = originalPath
        self.bundleIdentifier = bundleIdentifier
        self.originalName = originalName
        self.customName = customName
    }

    // Decodificação tolerante: campos novos em versões futuras não apagam a biblioteca.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        originalPath = try c.decode(String.self, forKey: .originalPath)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName)
            ?? URL(fileURLWithPath: originalPath).deletingPathExtension().lastPathComponent
        customName = try c.decodeIfPresent(String.self, forKey: .customName) ?? originalName
        hasCustomIcon = try c.decodeIfPresent(Bool.self, forKey: .hasCustomIcon) ?? false
        iconStyle = (try? c.decodeIfPresent(IconStyle.self, forKey: .iconStyle)) ?? .macOS
        adjustments = (try? c.decodeIfPresent(IconAdjustments.self, forKey: .adjustments)) ?? IconAdjustments()
        applyIconToOriginal = try c.decodeIfPresent(Bool.self, forKey: .applyIconToOriginal) ?? false
        renameOriginal = try c.decodeIfPresent(Bool.self, forKey: .renameOriginal) ?? false
        shortcutPath = try c.decodeIfPresent(String.self, forKey: .shortcutPath)
        lastApplied = try? c.decodeIfPresent(Date.self, forKey: .lastApplied)
        hasPendingChanges = try c.decodeIfPresent(Bool.self, forKey: .hasPendingChanges) ?? true
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
