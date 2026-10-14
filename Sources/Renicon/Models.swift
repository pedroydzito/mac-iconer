import Foundation

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
    /// Também aplica o ícone ao app original (aparece no Dock enquanto o app está aberto).
    var applyIconToOriginal = false
    /// Caminho do atalho gerado em ~/Applications/Renicon.
    var shortcutPath: String?
    var lastApplied: Date?
    /// Há edições que ainda não foram aplicadas ao atalho.
    var hasPendingChanges = true

    var displayName: String {
        customName.trimmingCharacters(in: .whitespaces).isEmpty ? originalName : customName
    }

    var originalURL: URL { URL(fileURLWithPath: originalPath) }
}
