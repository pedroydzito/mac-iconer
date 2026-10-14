import AppKit

enum IconRenderer {
    /// Renderiza a imagem num quadrado de `size` pixels, aplicando o estilo escolhido.
    static func pngData(for image: NSImage, size: Int, style: IconStyle) -> Data? {
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
            draw(image, macOSStyleIn: canvas)
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Gera uma NSImage já estilizada (usada nas pré-visualizações).
    static func styledImage(_ image: NSImage, style: IconStyle, size: Int = 512) -> NSImage {
        guard let data = pngData(for: image, size: size, style: style),
              let result = NSImage(data: data) else { return image }
        return result
    }

    /// Grade de ícones do macOS (Big Sur+): corpo de 824/1024 com cantos de ~185/1024.
    private static func draw(_ image: NSImage, macOSStyleIn canvas: NSRect) {
        let scale = canvas.width / 1024
        let body = NSRect(x: 100 * scale, y: 100 * scale + 6 * scale, width: 824 * scale, height: 824 * scale)
        let path = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 20 * scale
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: aspectFill(image.size, in: body, fit: false), from: .zero, operation: .sourceOver, fraction: 1)
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
    static func writeICNS(from image: NSImage, style: IconStyle, to destination: URL) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }

        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                guard let data = pngData(for: image, size: base * scale, style: style) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: iconset.appendingPathComponent(name))
            }
        }
        try? fm.removeItem(at: destination)
        try Shell.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", destination.path])
    }
}
