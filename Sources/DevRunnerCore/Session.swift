import Foundation

@MainActor
package final class Session {
    private var store: ConfigStore
    private let spawner: any ProcessSpawning
    private let ports: PortTool
    let terminationGrace: TimeInterval
    package let configRoot: URL
    package let userHome: URL
    package private(set) var projects: [Project] = []
    private var runtimes: [UUID: RunnerRuntime] = [:]
    private var logsStorage: [UUID: RingLog] = [:]
    private var handles: [UUID: any SpawnedHandle] = [:]
    private var lineBuffers: [UUID: LineBuffer] = [:]
    private var intentionalStops: Set<UUID> = []
    private var restartAfterStop: Set<UUID> = []
    private var projectIDByRunner: [UUID: UUID] = [:]
    package var onChange: (() -> Void)?
    private let sink = MainThreadSink()

    package init(
        store: ConfigStore,
        spawner: any ProcessSpawning,
        ports: PortTool,
        terminationGrace: TimeInterval = 4,
        configRoot: URL? = nil,
        userHome: URL? = nil
    ) {
        self.store = store
        self.spawner = spawner
        self.ports = ports
        self.terminationGrace = terminationGrace
        self.configRoot = configRoot ?? store.fileURL.deletingLastPathComponent()
        self.userHome = userHome ?? FileManager.default.homeDirectoryForCurrentUser
        projects = self.store.load()
        indexRunners()
        sink.bind(self)
    }

    package func logs(for runnerID: UUID) -> RingLog { logsStorage[runnerID] ?? RingLog() }
    package func runtime(for runnerID: UUID) -> RunnerRuntime { runtimes[runnerID] ?? .stopped }
    package func activeCount() -> Int { runtimes.values.filter { $0.phase == .running }.count }

    package func locate(_ runnerID: UUID) -> (project: Project, runner: RunnerConfig)? {
        for project in projects {
            if let runner = project.runners.first(where: { $0.id == runnerID }) {
                return (project, runner)
            }
        }
        return nil
    }

    package func removeRunner(runnerID: UUID) {
        stop(runnerID: runnerID)
        restartAfterStop.remove(runnerID)
        guard let projectIndex = projects.firstIndex(where: { $0.runners.contains { $0.id == runnerID } }) else { return }
        projects[projectIndex].runners.removeAll { $0.id == runnerID }
        if projects[projectIndex].runners.isEmpty {
            projects.remove(at: projectIndex)
        }
        forget(runnerID)
        indexRunners()
        persist()
        changed()
    }

    package func removeProject(projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        for runner in project.runners {
            stop(runnerID: runner.id)
            restartAfterStop.remove(runner.id)
            forget(runner.id)
        }
        projects.removeAll { $0.id == projectID }
        indexRunners()
        persist()
        changed()
    }

    package func addProject(_ project: Project) {
        projects.append(project)
        indexRunners()
        persist()
        changed()
    }

    package func updateRunner(_ runner: RunnerConfig, commandDidChange: Bool) {
        guard let projectIndex = projects.firstIndex(where: { $0.runners.contains { $0.id == runner.id } }),
              let runnerIndex = projects[projectIndex].runners.firstIndex(where: { $0.id == runner.id }) else { return }
        var updated = runner
        if commandDidChange { updated.commandEdited = true }
        if !updated.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.importNote = nil
        }
        projects[projectIndex].runners[runnerIndex] = updated
        indexRunners()
        persist()
        changed()
    }

    package func setDebugEnabled(_ enabled: Bool, runnerID: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.runners.contains { $0.id == runnerID } }),
              let runnerIndex = projects[projectIndex].runners.firstIndex(where: { $0.id == runnerID }) else { return }
        projects[projectIndex].runners[runnerIndex].debugEnabled = enabled
        persist()
        changed()
    }

    package func resync(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = projects[index]
        let scanned = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: URL(fileURLWithPath: project.rootPath, isDirectory: true),
            configRoot: configRoot,
            userHome: userHome
        ))
        projects[index].runners = IdeaImporter.resync(existing: project.runners, imported: scanned.runners, configRoot: configRoot)
        indexRunners()
        persist()
        changed()
    }

    /// Starts the runner. Returns a short failure reason for the UI, or `nil` if start was accepted or ignored.
    @discardableResult
    package func start(projectID: UUID, runnerID: UUID) -> String? {
        guard let runner = runner(projectID: projectID, runnerID: runnerID) else { return nil }
        let phase = runtime(for: runnerID).phase
        if phase == .starting || phase == .running { return nil }
        if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = runner.importNote ?? "Comando da completare."
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
            appendLog(message, runnerID: runnerID)
            return message
        }
        if let port = runner.portToCheck, ports.isBusy(port) {
            let message = "Porta \(port) occupata."
            appendLog(message, runnerID: runnerID)
            return message
        }
        var command = runner.command
        if runner.idea?.adapter == .tomcat {
            switch TomcatPreparer.prepare(runner: runner) {
            case .failure(let error):
                setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
                appendLog(error.description, runnerID: runnerID)
                return error.description
            case .success(let launch):
                command = launch.command
            }
        }
        let environment = DebugEnv.apply(runner: runner, env: runner.env)
        setRuntime(runnerID, RunnerRuntime(phase: .starting, pid: nil))
        do {
            let handle = try spawner.spawn(SpawnRequest(
                command: command,
                workingDirectory: runner.workingDirectory,
                environment: environment
            ))
            handles[runnerID] = handle
            lineBuffers[runnerID] = LineBuffer()
            let sink = self.sink
            handle.readOutput { chunk in sink.consume(chunk, runnerID: runnerID) }
            handle.onExit { code in sink.exited(code, runnerID: runnerID) }
            setRuntime(runnerID, RunnerRuntime(phase: .running, pid: handle.pid))
            return nil
        } catch {
            handles[runnerID] = nil
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
            let message = (error as? SpawnError)?.description ?? error.localizedDescription
            appendLog(message, runnerID: runnerID)
            return message
        }
    }

    package func stop(runnerID: UUID) {
        let phase = runtime(for: runnerID).phase
        guard phase == .starting || phase == .running else { return }
        guard let handle = handles[runnerID] else {
            setRuntime(runnerID, .stopped)
            return
        }
        intentionalStops.insert(runnerID)
        handle.signalGroup(terminateGrace: terminationGrace)
    }

    @discardableResult
    package func restart(projectID: UUID, runnerID: UUID) -> String? {
        projectIDByRunner[runnerID] = projectID
        let phase = runtime(for: runnerID).phase
        if phase == .starting || phase == .running {
            restartAfterStop.insert(runnerID)
            stop(runnerID: runnerID)
            return nil
        }
        return start(projectID: projectID, runnerID: runnerID)
    }

    package func stopAll() {
        for project in projects {
            for runner in project.runners { stop(runnerID: runner.id) }
        }
    }

    package func stopAllForTermination() {
        let current = Array(handles.values)
        let grace = terminationGrace
        let group = DispatchGroup()
        for handle in current {
            group.enter()
            DispatchQueue.global().async {
                handle.stopAndWait(grace: grace)
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + grace + 2)
    }

    package func freePort(runnerID: UUID) {
        guard let runner = locate(runnerID)?.runner, let port = runner.portToCheck else { return }
        let pids = ports.free(port)
        if pids.isEmpty {
            appendLog("Nessun processo in ascolto sulla porta \(port).", runnerID: runnerID)
        } else {
            appendLog("Porta \(port) liberata.", runnerID: runnerID)
        }
    }

    package func clearLog(runnerID: UUID) {
        logsStorage[runnerID] = RingLog()
        changed()
    }

    package func configFileURLForOpen() throws -> URL {
        try store.prepareForOpen()
        return store.fileURL
    }

    func consumeOutput(_ chunk: String, runnerID: UUID) {
        var buffer = lineBuffers[runnerID] ?? LineBuffer()
        let lines = buffer.consume(chunk)
        lineBuffers[runnerID] = buffer
        guard !lines.isEmpty else { return }
        var log = logsStorage[runnerID] ?? RingLog()
        log.append(lines: lines)
        logsStorage[runnerID] = log
        changed()
    }

    func consumeExit(_ code: Int32, runnerID: UUID) {
        if var buffer = lineBuffers.removeValue(forKey: runnerID) {
            let tail = buffer.flush()
            if !tail.isEmpty {
                var log = logsStorage[runnerID] ?? RingLog()
                log.append(lines: tail)
                logsStorage[runnerID] = log
            }
        }
        handles[runnerID] = nil
        let intentional = intentionalStops.remove(runnerID) != nil
        if intentional || code == 0 {
            setRuntime(runnerID, .stopped)
        } else {
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
        }
        if restartAfterStop.remove(runnerID) != nil, let projectID = projectIDByRunner[runnerID] {
            start(projectID: projectID, runnerID: runnerID)
        }
    }

    private func runner(projectID: UUID, runnerID: UUID) -> RunnerConfig? {
        projects.first { $0.id == projectID }?.runners.first { $0.id == runnerID }
    }

    private func appendLog(_ line: String, runnerID: UUID) {
        var log = logsStorage[runnerID] ?? RingLog()
        log.append(lines: [line])
        logsStorage[runnerID] = log
        changed()
    }

    private func setRuntime(_ runnerID: UUID, _ runtime: RunnerRuntime) {
        runtimes[runnerID] = runtime
        changed()
    }

    private func forget(_ runnerID: UUID) {
        logsStorage[runnerID] = nil
        runtimes[runnerID] = nil
        lineBuffers[runnerID] = nil
    }

    private func indexRunners() {
        projectIDByRunner = [:]
        for project in projects {
            for runner in project.runners { projectIDByRunner[runner.id] = project.id }
        }
    }

    private func persist() { try? store.save(projects) }
    private func changed() { onChange?() }
}

final class MainThreadSink: @unchecked Sendable {
    weak var session: Session?
    func bind(_ session: Session) { self.session = session }

    func consume(_ chunk: String, runnerID: UUID) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.session?.consumeOutput(chunk, runnerID: runnerID)
            }
        }
    }

    func exited(_ code: Int32, runnerID: UUID) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.session?.consumeExit(code, runnerID: runnerID)
            }
        }
    }
}
