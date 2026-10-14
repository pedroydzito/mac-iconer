import AppKit
import SwiftUI

/// Verifica as Releases do GitHub e instala novas versões do próprio Renicon.
@MainActor
final class Updater: ObservableObject {
    static let repository = "pedroydzito/mac-renicon"

    struct Release: Equatable, Identifiable {
        var id: String { version }
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum Phase: Equatable {
        case idle, checking, downloading, installing
        case upToDate
        case failed(String)
    }

    @Published var available: Release?
    @Published var phase: Phase = .idle
    @Published var lastCheck: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date

    @Published var autoCheck = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoCheck, forKey: "autoCheckUpdates")
            if autoCheck { start() } else { timer?.invalidate() }
        }
    }
    private var skippedVersion: String {
        get { UserDefaults.standard.string(forKey: "skippedVersion") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "skippedVersion") }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var timer: Timer?

    func start() {
        guard autoCheck else { return }
        Task { await check(userInitiated: false) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoCheck else { return }
                await self.check(userInitiated: false)
            }
        }
    }

    func check(userInitiated: Bool) async {
        phase = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                phase = .upToDate
                return
            }
            let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: "lastUpdateCheck")

            let version = json.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isVersion(version, newerThan: Self.currentVersion),
                  let asset = json.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                phase = .upToDate
                return
            }
            if !userInitiated && version == skippedVersion {
                phase = .idle
                return
            }
            phase = .idle
            available = Release(version: version, notes: json.body ?? "",
                                downloadURL: asset.browser_download_url, pageURL: json.html_url)
        } catch {
            phase = userInitiated ? .failed("Não foi possível verificar: \(error.localizedDescription)") : .idle
        }
    }

    func skip(_ release: Release) {
        skippedVersion = release.version
        available = nil
    }

    /// Baixa o .zip, substitui o app atual e reabre.
    func install(_ release: Release) async {
        phase = .downloading
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("RenUpdate-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (downloaded, _) = try await URLSession.shared.download(from: release.downloadURL)
            let zip = work.appendingPathComponent("Renicon.zip")
            try fm.moveItem(at: downloaded, to: zip)

            phase = .installing
            let current = Bundle.main.bundleURL
            if current.path.contains("/AppTranslocation/") || current.path.hasPrefix("/Volumes/") {
                throw NSError(domain: "Renicon", code: 4, userInfo: [NSLocalizedDescriptionKey:
                    "Mova o Renicon para a pasta Aplicativos antes de atualizar."])
            }
            try await Task.detached {
                try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            }.value
            guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "Renicon", code: 2, userInfo: [NSLocalizedDescriptionKey: "O arquivo da atualização não contém o app."])
            }
            try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
                throw NSError(domain: "Renicon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sem permissão para substituir o app em \(current.deletingLastPathComponent().path)."])
            }

            // Script que espera o Renicon fechar, troca o app e abre a nova versão.
            let script = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            rm -rf "$2"
            /usr/bin/ditto "$1" "$2"
            /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
            /usr/bin/open "$2"
            rm -rf "$3"
            """
            let scriptURL = work.appendingPathComponent("install.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path, newApp.path, current.path, work.path]
            try process.run()
            relaunch()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fecha o Renicon para o instalador trocar o app. Fecha a janela de atualização
    /// antes (com ela aberta o macOS pode ignorar o pedido) e, se ainda assim o app
    /// não fechar, encerra o processo.
    private func relaunch() {
        available = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.windows.forEach { $0.close() }
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }
}

struct UpdateSheet: View {
    @EnvironmentObject private var updater: Updater
    let release: Updater.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uma nova versão do Renicon está disponível!")
                        .font(.headline)
                    Text("O Renicon \(release.version) está disponível — você tem a versão \(Updater.currentVersion). Deseja atualizar agora?")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !release.notes.isEmpty {
                Text("Novidades").font(.subheadline.weight(.semibold))
                ScrollView {
                    Text((try? AttributedString(markdown: release.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 160)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            switch updater.phase {
            case .downloading: ProgressView("Baixando…").progressViewStyle(.linear)
            case .installing: ProgressView("Instalando…").progressViewStyle(.linear)
            case .failed(let message): Text(message).foregroundStyle(.red).font(.callout)
            default: EmptyView()
            }
            HStack {
                Button("Pular Esta Versão") { updater.skip(release) }
                Spacer()
                Button("Lembrar Depois") { updater.available = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Instalar e Reiniciar") { Task { await updater.install(release) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(updater.phase == .downloading || updater.phase == .installing)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
