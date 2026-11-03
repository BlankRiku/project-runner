import Darwin
import Foundation

struct LsofCommand: Equatable, Sendable {
    var port: Int

    var executable: String { "/usr/sbin/lsof" }

    var arguments: [String] { ["-ti", "tcp:\(port)"] }
}

enum LsofOutput {
    static func parsePids(_ text: String) -> [Int32] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return Int32(trimmed)
        }
    }
}

struct PortTool: Sendable {
    var run: @Sendable (_ executable: String, _ arguments: [String]) -> String
    var signal: @Sendable (_ pid: Int32, _ signal: Int32) -> Void

    func isBusy(_ port: Int) -> Bool {
        let command = LsofCommand(port: port)
        return !LsofOutput.parsePids(run(command.executable, command.arguments)).isEmpty
    }

    @discardableResult
    func free(_ port: Int) -> [Int32] {
        let command = LsofCommand(port: port)
        let pids = LsofOutput.parsePids(run(command.executable, command.arguments))
        for pid in pids {
            signal(pid, SIGKILL)
        }
        return pids
    }

    static func live() -> PortTool {
        PortTool(
            run: { executable, arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(decoding: data, as: UTF8.self)
                } catch {
                    return ""
                }
            },
            signal: { pid, sig in
                _ = Darwin.kill(pid, sig)
            }
        )
    }
}
