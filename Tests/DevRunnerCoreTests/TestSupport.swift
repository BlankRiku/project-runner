import Foundation

enum TestSupport {
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

struct TestPaths: Sendable {
    var home: URL
    var catalinaHome: String
    var javaHome: String

    static func load() throws -> TestPaths {
        let values = mergedValues()
        let homePath = try directory("DEV_RUNNER_HOME", in: values)
        return TestPaths(
            home: URL(fileURLWithPath: homePath, isDirectory: true),
            catalinaHome: try directory("DEV_RUNNER_CATALINA_HOME", in: values),
            javaHome: try directory("DEV_RUNNER_JAVA_HOME", in: values)
        )
    }

    func userHomeMacro(_ absolutePath: String) -> String {
        let prefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        if absolutePath == home.path { return "$USER_HOME$" }
        if absolutePath.hasPrefix(prefix) {
            return "$USER_HOME$/" + absolutePath.dropFirst(prefix.count)
        }
        return absolutePath
    }

    private static func mergedValues() -> [String: String] {
        var values: [String: String] = [:]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) {
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let body = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
                let parts = body.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                values[parts[0].trimmingCharacters(in: .whitespaces)] = unquote(parts[1])
            }
        }
        for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("DEV_RUNNER_") && !value.isEmpty {
            values[key] = value
        }
        return values
    }

    private static func directory(_ key: String, in values: [String: String]) throws -> String {
        guard var path = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TestPathError.missing(key)
        }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TestPathError.notDirectory(key, path)
        }
        return path
    }

    private static func unquote(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

enum TestPathError: Error, CustomStringConvertible {
    case missing(String)
    case notDirectory(String, String)

    var description: String {
        switch self {
        case .missing(let key):
            return "Manca \(key). Copia .env.example in .env e inserisci il percorso."
        case .notDirectory(let key, let path):
            return "\(key) non è una cartella: \(path)"
        }
    }
}
