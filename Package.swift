// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Renicon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Renicon", path: "Sources/Renicon"),
        // Executável copiado para dentro de cada atalho criado.
        .executableTarget(name: "RenLauncher", path: "Sources/RenLauncher"),
    ]
)
