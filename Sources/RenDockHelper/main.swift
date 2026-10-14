import AppKit
import RenCore

// Ajudante do Dock do Renicon. Não tem ícone nem janela e fica parado até o macOS avisar
// que um app abriu ou fechou. Regra: se o app está aberto (por qualquer caminho), ele ocupa
// o lugar do atalho no Dock; quando fecha, o atalho volta para a mesma posição.

final class DockHelper {
    private let work = DispatchQueue(label: "com.renicon.dockhelper.work")
    private var pending: DispatchWorkItem?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, DockSwap.load().contains(where: { $0.bundleID == id }) else { return }
                self?.schedule(after: 0.2)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: DockSwap.reloadNotification, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: 0.5)
        }
        // Ao iniciar (login ou depois de uma falha), deixa o Dock de acordo com a regra.
        schedule(after: 1)
    }

    private func schedule(after delay: Double) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func reconcile() {
        let items = DockSwap.load()
        guard !items.isEmpty else { return }
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated }
            .compactMap(\.bundleIdentifier))
        let resolved = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)?.path ?? item.original)
        })
        work.async {
            let changes = DockSwap.changes(for: items, running: running) { resolved[$0.bundleID] ?? $0.original }
            if !changes.isEmpty { DockManager.replaceMany(changes) }
        }
    }
}

let helper = DockHelper()
helper.start()
RunLoop.main.run()
