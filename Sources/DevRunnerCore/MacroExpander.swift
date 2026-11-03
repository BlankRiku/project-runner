import Foundation

enum MacroExpander {
    static func expand(_ value: String, projectRoot: URL, userHome: URL) -> String {
        value
            .replacingOccurrences(of: "$PROJECT_DIR$", with: projectRoot.path)
            .replacingOccurrences(of: "$USER_HOME$", with: userHome.path)
    }
}

enum ShellWords {
    static func quote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._+-:@")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
