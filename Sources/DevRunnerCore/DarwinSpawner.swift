#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

package struct SpawnRequest: Equatable, Sendable {
    var command: String
    var workingDirectory: String
    var environment: [String: String]
    var shellPath: String = "/bin/zsh"
    var shellArguments: [String] = ["-l", "-c"]
}

package protocol SpawnedHandle: AnyObject, Sendable {
    var pid: Int32 { get }
    func readOutput(_ handler: @escaping @Sendable (String) -> Void)
    func onExit(_ handler: @escaping @Sendable (Int32) -> Void)
    func signalGroup(terminateGrace seconds: TimeInterval)
    func stopAndWait(grace: TimeInterval)
    func groupAlive() -> Bool
}

package protocol ProcessSpawning: Sendable {
    func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle
}

enum SpawnError: Error, Equatable, CustomStringConvertible {
    case pipe
    case setup(String)
    case spawn(Int32)

    var description: String {
        switch self {
        case .pipe:
            return "Pipe di log non disponibile."
        case .setup(let message):
            return "Preparazione del processo non riuscita: \(message)"
        case .spawn(let code):
            return "Avvio non riuscito (\(code))."
        }
    }
}

#if os(macOS)
package struct DarwinProcessSpawner: ProcessSpawning {
    package init() {}

    package func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle {
        var fds = [Int32](repeating: 0, count: 2)
        guard pipe(&fds) == 0 else { throw SpawnError.pipe }
        let readFD = fds[0]
        let writeFD = fds[1]
        var actions: posix_spawn_file_actions_t?
        var attr: posix_spawnattr_t?
        var actionsReady = false
        var attrReady = false
        var transferred = false
        defer {
            if actionsReady { posix_spawn_file_actions_destroy(&actions) }
            if attrReady { posix_spawnattr_destroy(&attr) }
            if !transferred {
                close(readFD)
                close(writeFD)
            }
        }
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw SpawnError.setup("file actions") }
        actionsReady = true
        guard posix_spawnattr_init(&attr) == 0 else { throw SpawnError.setup("attributi") }
        attrReady = true
        guard posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, readFD) == 0,
              posix_spawn_file_actions_addclose(&actions, writeFD) == 0 else {
            throw SpawnError.setup("redirect")
        }
        let chdirResult = request.workingDirectory.withCString { addChdir(&actions, $0) }
        guard chdirResult == 0 else { throw SpawnError.setup("cartella di lavoro") }
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attr, 0) == 0 else {
            throw SpawnError.setup("process group")
        }
        let argv = [request.shellPath] + request.shellArguments + [request.command]
        let env = mergedEnvironment(request.environment)
        var pid: pid_t = 0
        let code: Int32 = CStringBuffer.with(argv) { argvPtr in
            CStringBuffer.with(env) { envPtr in
                request.shellPath.withCString { path in
                    posix_spawn(&pid, path, &actions, &attr, argvPtr, envPtr)
                }
            }
        }
        guard code == 0 else { throw SpawnError.spawn(code) }
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        close(writeFD)
        transferred = true
        let handle = DarwinProcessHandle(pid: pid, readFD: readFD)
        handle.start()
        return handle
    }

    private func mergedEnvironment(_ overlay: [String: String]) -> [String] {
        var dict = ProcessInfo.processInfo.environment
        for (key, value) in overlay where !key.isEmpty {
            dict[key] = value
        }
        return dict.map { "\($0.key)=\($0.value)" }
    }
}

private func addChdir(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>, _ path: UnsafePointer<CChar>) -> Int32 {
    if #available(macOS 26.0, *) {
        return posix_spawn_file_actions_addchdir(actions, path)
    } else {
        return posix_spawn_file_actions_addchdir_np(actions, path)
    }
}

private enum CStringBuffer {
    static func with<R>(_ values: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        let allocated: [UnsafeMutablePointer<CChar>?] = values.map { strdup($0) }
        defer { allocated.forEach { free($0) } }
        var pointers = allocated
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

final class DarwinProcessHandle: SpawnedHandle, @unchecked Sendable {
    let pid: Int32
    private let lock = NSLock()
    private var outputHandler: (@Sendable (String) -> Void)?
    private var exitHandler: (@Sendable (Int32) -> Void)?
    private var buffered: [String] = []
    private var readFD: Int32
    private var source: DispatchSourceProcess?

    init(pid: Int32, readFD: Int32) {
        self.pid = pid
        self.readFD = readFD
    }

    func start() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            let result = waitpid(self.pid, &status, WNOHANG)
            guard result == self.pid else { return }
            self.lock.lock()
            let handler = self.exitHandler
            self.lock.unlock()
            handler?(Self.exitCode(status))
        }
        self.source = source
        source.resume()
        let fd = readFD
        Thread.detachNewThread { [weak self] in
            self?.readLoop(fd: fd)
        }
    }

    func readOutput(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        outputHandler = handler
        let pending = buffered
        buffered.removeAll()
        lock.unlock()
        pending.forEach(handler)
    }

    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        exitHandler = handler
        lock.unlock()
    }

    func signalGroup(terminateGrace seconds: TimeInterval) {
        let group = pid
        _ = Darwin.kill(-group, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if Darwin.kill(-group, 0) == 0 {
                _ = Darwin.kill(-group, SIGKILL)
            }
        }
    }

    func stopAndWait(grace: TimeInterval) {
        _ = Darwin.kill(-pid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if Darwin.kill(-pid, 0) != 0 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if Darwin.kill(-pid, 0) == 0 {
            _ = Darwin.kill(-pid, SIGKILL)
        }
    }

    func groupAlive() -> Bool {
        Darwin.kill(-pid, 0) == 0
    }

    private func readLoop(fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            deliver(String(decoding: data, as: UTF8.self))
        }
        closeRead()
    }

    private func deliver(_ text: String) {
        lock.lock()
        let handler = outputHandler
        if handler == nil {
            buffered.append(text)
        }
        lock.unlock()
        handler?(text)
    }

    private func closeRead() {
        lock.lock()
        let fd = readFD
        readFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
    }

    deinit { closeRead() }

    private static func exitCode(_ status: Int32) -> Int32 {
        if status & 0x7f == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + (status & 0x7f)
    }
}
#endif
