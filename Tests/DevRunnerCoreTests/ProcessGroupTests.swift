#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest
@testable import DevRunnerCore

#if os(macOS)
final class ProcessGroupTests: XCTestCase {
    func testLoginShellCannotReplaceTheProjectJdk() throws {
        let root = try TestSupport.makeDirectory()
        defer { TestSupport.remove(root) }
        let zdot = root.appendingPathComponent("zdot", isDirectory: true)
        let projectJava = root.appendingPathComponent("project-jdk").path
        try TestSupport.write("export JAVA_HOME=/machine/jdk\nexport JRE_HOME=/machine/jdk\n", to: zdot.appendingPathComponent(".zprofile"))
        let spawner = DarwinProcessSpawner()
        let handle = try spawner.spawn(SpawnRequest(
            command: "printf '%s\\n%s\\n' \"$JAVA_HOME\" \"$JRE_HOME\"",
            workingDirectory: root.path,
            environment: [
                "JAVA_HOME": projectJava,
                "ZDOTDIR": zdot.path
            ],
            shellPath: "/bin/zsh",
            shellArguments: ["-l", "-c"]
        ))
        defer {
            kill(-handle.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(handle.pid, &status, WNOHANG)
        }
        let box = TextBox()
        let ready = expectation(description: "java home")
        ready.assertForOverFulfill = false
        handle.readOutput { chunk in
            box.append(chunk)
            if box.text.split(whereSeparator: \.isNewline).count >= 2 { ready.fulfill() }
        }
        handle.onExit { _ in }
        wait(for: [ready], timeout: 8)
        let lines = box.text.split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertEqual(lines, [projectJava, projectJava])
    }

    func testBackgroundSleepDiesWithItsGroup() throws {
        let spawner = DarwinProcessSpawner()
        let handle = try spawner.spawn(SpawnRequest(
            command: "sleep 30 & echo $!; wait",
            workingDirectory: "/tmp",
            environment: [:],
            shellPath: "/bin/zsh",
            shellArguments: ["-f", "-c"]
        ))
        defer {
            kill(-handle.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(handle.pid, &status, WNOHANG)
        }
        let box = TextBox()
        let ready = expectation(description: "pid")
        ready.assertForOverFulfill = false
        handle.readOutput { chunk in
            box.append(chunk)
            if box.text.contains("\n") { ready.fulfill() }
        }
        wait(for: [ready], timeout: 3)
        let sleepPid = box.text.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.first
        let sleep = try XCTUnwrap(sleepPid)
        XCTAssertEqual(getpgid(handle.pid), handle.pid)
        XCTAssertEqual(getpgid(sleep), handle.pid)
        handle.signalGroup(terminateGrace: 1)
        let deadline = Date().addingTimeInterval(2)
        var dead = false
        while Date() < deadline {
            if kill(sleep, 0) != 0 && !handle.groupAlive() {
                dead = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(dead)
    }

    func testIgnoredTermDiesAfterSigkill() throws {
        let spawner = DarwinProcessSpawner()
        let handle = try spawner.spawn(SpawnRequest(
            command: "trap '' TERM; echo READY; while true; do sleep 0.2; done",
            workingDirectory: "/tmp",
            environment: [:],
            shellPath: "/bin/zsh",
            shellArguments: ["-f", "-c"]
        ))
        defer {
            kill(-handle.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(handle.pid, &status, WNOHANG)
        }
        let box = TextBox()
        let ready = expectation(description: "ready")
        ready.assertForOverFulfill = false
        handle.readOutput { chunk in
            box.append(chunk)
            if box.text.contains("READY") { ready.fulfill() }
        }
        wait(for: [ready], timeout: 3)
        XCTAssertEqual(getpgid(handle.pid), handle.pid)
        handle.signalGroup(terminateGrace: 0.4)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertTrue(handle.groupAlive())
        let deadline = Date().addingTimeInterval(1.5)
        var dead = false
        while Date() < deadline {
            if !handle.groupAlive() {
                dead = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(dead)
    }
}

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }
}
#endif
