import RenCore
import AppKit

enum IconRenderer {
    /// Renderiza a imagem num quadrado de `size` pixels, aplicando o estilo escolhido.
    static func pngData(for image: NSImage, size: Int, style: IconStyle, adjustments: IconAdjustments = IconAdjustments()) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let canvas = NSRect(x: 0, y: 0, width: size, height: size)
        switch style {
        case .original:
            image.draw(in: aspectFill(image.size, in: canvas, fit: true), from: .zero, operation: .sourceOver, fraction: 1)
        case .macOS:
            draw(image, macOSStyleIn: canvas, adjustments: adjustments)
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Gera uma NSImage já estilizada (usada nas pré-visualizações).
    static func styledImage(_ image: NSImage, style: IconStyle, adjustments: IconAdjustments = IconAdjustments(), size: Int = 512) -> NSImage {
        guard let data = pngData(for: image, size: size, style: style, adjustments: adjustments),
              let result = NSImage(data: data) else { return image }
        return result
    }

    /// Grade de ícones do macOS (Big Sur+): corpo de 824/1024 com cantos de ~185/1024.
    private static func draw(_ image: NSImage, macOSStyleIn canvas: NSRect, adjustments: IconAdjustments) {
        let scale = canvas.width / 1024
        let body = NSRect(x: 100 * scale, y: 100 * scale + 6 * scale, width: 824 * scale, height: 824 * scale)
        let path = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 20 * scale
        shadow.set()
        adjustments.backgroundColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let zoom = CGFloat(min(max(adjustments.zoom, 0.3), 2))
        let target = body.insetBy(dx: body.width * (1 - zoom) / 2, dy: body.height * (1 - zoom) / 2)
        // Abaixo de 100% a imagem inteira cabe (com margem); acima, ela é aproximada.
        image.draw(in: aspectFill(image.size, in: target, fit: zoom < 1), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func aspectFill(_ size: NSSize, in rect: NSRect, fit: Bool) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let ratio = fit ? min(rect.width / size.width, rect.height / size.height)
                        : max(rect.width / size.width, rect.height / size.height)
        let w = size.width * ratio, h = size.height * ratio
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Cria um arquivo .icns com todos os tamanhos exigidos pelo macOS.
    static func writeICNS(from image: NSImage, style: IconStyle, adjustments: IconAdjustments = IconAdjustments(), to destination: URL) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }

        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                guard let data = pngData(for: image, size: base * scale, style: style, adjustments: adjustments) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: iconset.appendingPathComponent(name))
            }
        }
        try? fm.removeItem(at: destination)
        try Shell.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", destination.path])
    }
}

extension IconRenderer {
    /// Cria um ícone com um emoji ou letra(s) sobre uma cor (o formato macOS é aplicado depois).
    static func makeIcon(text: String, background: NSColor) -> NSImage {
        let size: CGFloat = 1024
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        background.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        let trimmed = String(text.trimmingCharacters(in: .whitespaces).prefix(2))
        let isEmoji = trimmed.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        let rgb = background.usingColorSpace(.sRGB) ?? .white
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        let fontSize: CGFloat = isEmoji ? 600 : (trimmed.count > 1 ? 440 : 600)
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        if !isEmoji, let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: rounded, size: fontSize) ?? font
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: luminance > 0.6 ? NSColor.black.withAlphaComponent(0.85) : NSColor.white,
        ]
        let string = NSAttributedString(string: isEmoji ? trimmed : trimmed.uppercased(), attributes: attributes)
        let bounds = string.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
        string.draw(at: NSPoint(x: (size - bounds.width) / 2 - bounds.minX, y: (size - bounds.height) / 2 - bounds.minY))
        image.unlockFocus()
        return image
    }
}
