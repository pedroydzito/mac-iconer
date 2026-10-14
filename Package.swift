// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Renicon",
    platforms: [.macOS(.v14)],
    targets: [
        // Código compartilhado: edição do Dock e comandos do sistema.
        .target(name: "RenCore", path: "Sources/RenCore"),
        .executableTarget(name: "Renicon", dependencies: ["RenCore"], path: "Sources/Renicon"),
        // Executável copiado para dentro de cada atalho criado.
        .executableTarget(name: "RenLauncher", path: "Sources/RenLauncher"),
        // Ajudante que troca atalho ⇄ app no Dock quando o app abre ou fecha.
        .executableTarget(name: "RenDockHelper", dependencies: ["RenCore"], path: "Sources/RenDockHelper"),
    ]
)
