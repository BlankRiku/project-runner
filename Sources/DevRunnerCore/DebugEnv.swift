import Foundation

enum DebugEnv {
    static func agent(port: Int) -> String {
        "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:\(port)"
    }

    static func apply(runner: RunnerConfig, env: [String: String]) -> [String: String] {
        guard runner.debugEnabled else { return env }
        let key: String
        switch runner.debugInjection {
        case .none:
            return env
        case .javaToolOptions:
            key = "JAVA_TOOL_OPTIONS"
        case .catalinaOpts:
            key = "CATALINA_OPTS"
        }
        let token = agent(port: runner.debugPort)
        var copy = env
        let current = copy[key] ?? ""
        if current.contains(token) {
            return copy
        }
        copy[key] = current.isEmpty ? token : current + " " + token
        return copy
    }
}
