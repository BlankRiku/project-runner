import Foundation

struct TomcatLaunch: Equatable, Sendable {
    var command: String
}

enum TomcatPrepareError: Error, Equatable, CustomStringConvertible {
    case missingCatalinaHome
    case missingJavaHome
    case missingArtifactPath
    case missingCatalinaBase
    case missingConf
    case copyFailed(String)

    var description: String {
        switch self {
        case .missingCatalinaHome:
            return "CATALINA_HOME non trovato."
        case .missingJavaHome:
            return "JRE non trovato sul disco."
        case .missingArtifactPath:
            return "Percorso artifact mancante."
        case .missingCatalinaBase:
            return "CATALINA_BASE mancante."
        case .missingConf:
            return "Configurazione Tomcat incompleta: manca conf."
        case .copyFailed(let message):
            return "Copia di conf non riuscita: \(message)"
        }
    }
}

enum TomcatPreparer {
    static func contextFileName(contextPath: String) -> String {
        var path = contextPath
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { return "ROOT.xml" }
        path = path.replacingOccurrences(of: "/", with: "#")
        return path + ".xml"
    }

    static func prepare(runner: RunnerConfig, fileManager: FileManager = .default) -> Result<TomcatLaunch, TomcatPrepareError> {
        let home = runner.env["CATALINA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if home.isEmpty { return .failure(.missingCatalinaHome) }
        if let java = runner.env["JAVA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !java.isEmpty {
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: java, isDirectory: &isDir) || !isDir.boolValue {
                return .failure(.missingJavaHome)
            }
        }
        let docBase = runner.tomcatDocBase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if docBase.isEmpty { return .failure(.missingArtifactPath) }
        let basePath = runner.env["CATALINA_BASE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if basePath.isEmpty { return .failure(.missingCatalinaBase) }
        let base = URL(fileURLWithPath: basePath, isDirectory: true)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            for folder in ["logs", "temp", "webapps", "work"] {
                try fileManager.createDirectory(at: base.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
            }
            let confDest = base.appendingPathComponent("conf", isDirectory: true)
            if !fileManager.fileExists(atPath: confDest.path) {
                let confSource = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("conf", isDirectory: true)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: confSource.path, isDirectory: &isDir), isDir.boolValue else {
                    return .failure(.missingConf)
                }
                try fileManager.copyItem(at: confSource, to: confDest)
            }
            let fileName = contextFileName(contextPath: runner.tomcatContextPath ?? "/")
            let localhost = confDest.appendingPathComponent("Catalina/localhost", isDirectory: true)
            try fileManager.createDirectory(at: localhost, withIntermediateDirectories: true)
            try contextXML(docBase: docBase).write(to: localhost.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
        let stored = runner.command
        let command: String
        if runner.commandEdited || directoryExists(docBase, fileManager) {
            command = stored
        } else {
            command = "mvn -DskipTests -q war:exploded && \(stored)"
        }
        return .success(TomcatLaunch(command: command))
    }

    private static func directoryExists(_ path: String, _ fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func contextXML(docBase: String) -> String {
        let escaped = docBase
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Context docBase="\(escaped)" />
        """
    }
}
