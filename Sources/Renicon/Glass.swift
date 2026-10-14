import SwiftUI

// Liquid Glass no macOS 26+; material translúcido nas versões anteriores.

extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.makeGlass(interactive: interactive, tint: tint), in: shape)
        } else {
            self
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    func glass(interactive: Bool = false, tint: Color? = nil) -> some View {
        glass(in: Capsule(), interactive: interactive, tint: tint)
    }

    @available(macOS 26.0, *)
    private static func makeGlass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// Agrupa elementos de vidro para que se fundam como no macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Fundo escuro com as cores do ícone selecionado desfocadas, no estilo do macOS.
struct Backdrop: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90)
                    .opacity(0.55)
                    .scaleEffect(1.4)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: image)
    }
}
