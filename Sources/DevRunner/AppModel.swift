import DevRunnerCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static weak var terminationTarget: AppModel?
    let session: Session
    @Published private(set) var revision = 0
    private var pending = false
    private var lastRefresh = Date.distantPast

    init(session: Session) {
        self.session = session
        Self.terminationTarget = self
        session.onChange = { [weak self] in
            Task { @MainActor in self?.schedule() }
        }
    }

    convenience init() {
        let store = ConfigStore(fileURL: ConfigStore.defaultFileURL)
        let session = Session(store: store, spawner: DarwinProcessSpawner(), ports: PortTool.live())
        self.init(session: session)
    }

    var projects: [Project] { _ = revision; return session.projects }
    var activeCount: Int { _ = revision; return session.activeCount() }

    func runtime(for runnerID: UUID) -> RunnerRuntime { _ = revision; return session.runtime(for: runnerID) }
    func logs(for runnerID: UUID) -> RingLog { _ = revision; return session.logs(for: runnerID) }
    func locate(_ runnerID: UUID) -> (project: Project, runner: RunnerConfig)? {
        _ = revision
        return session.locate(runnerID)
    }

    private func schedule() {
        let delta = Date().timeIntervalSince(lastRefresh)
        if delta >= 0.2 {
            lastRefresh = Date()
            revision += 1
            return
        }
        if pending { return }
        pending = true
        let wait = 0.2 - delta
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self.pending = false
            self.lastRefresh = Date()
            self.revision += 1
        }
    }
}
