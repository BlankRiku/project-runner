import Foundation
#if !canImport(Darwin) && canImport(FoundationXML)
import FoundationXML
#endif

enum JetBrainsLookup {
    static func catalinaHome(serverName: String, files: [URL], projectRoot: URL, userHome: URL) -> String? {
        for file in files {
            guard let document = try? XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace]) else { continue }
            if let home = home(in: document, serverName: serverName) {
                let expanded = MacroExpander.expand(home, projectRoot: projectRoot, userHome: userHome)
                if !expanded.isEmpty { return expanded }
            }
        }
        return nil
    }

    static func jdkHome(name: String, files: [URL], projectRoot: URL, userHome: URL) -> String? {
        if name.contains("/") || name.hasPrefix("$") {
            let expanded = MacroExpander.expand(name, projectRoot: projectRoot, userHome: userHome)
            return expanded.isEmpty ? nil : expanded
        }
        for file in files {
            guard let document = try? XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace]) else { continue }
            guard let nodes = try? document.nodes(forXPath: "//jdk") else { continue }
            for case let element as XMLElement in nodes {
                let jdkName = element.elements(forName: "name").first?.attribute(forName: "value")?.stringValue
                guard jdkName == name else { continue }
                if let home = element.elements(forName: "homePath").first?.attribute(forName: "value")?.stringValue {
                    let expanded = MacroExpander.expand(home, projectRoot: projectRoot, userHome: userHome)
                    if !expanded.isEmpty { return expanded }
                }
            }
        }
        return nil
    }

    static func discover(userHome: URL) -> (servers: [URL], jdks: [URL]) {
        let root = userHome.appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        guard let products = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }
        var servers: [URL] = []
        var jdks: [URL] = []
        for product in products {
            let options = product.appendingPathComponent("options", isDirectory: true)
            for name in ["applicationServers.xml", "javaeeAppServers.xml"] {
                let url = options.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    servers.append(url)
                }
            }
            let jdk = options.appendingPathComponent("jdk.table.xml")
            if FileManager.default.fileExists(atPath: jdk.path) {
                jdks.append(jdk)
            }
        }
        return (sortByModification(servers), sortByModification(jdks))
    }

    private static func home(in document: XMLDocument, serverName: String) -> String? {
        if let nodes = try? document.nodes(forXPath: "//ServerSettingsImpl") {
            for case let element as XMLElement in nodes {
                guard optionValue(element, name: "NAME") == serverName else { continue }
                if let home = optionValue(element, name: "HOME"), !home.isEmpty {
                    return home
                }
            }
        }
        if let nodes = try? document.nodes(forXPath: "//ServerDK") {
            for case let element as XMLElement in nodes {
                guard element.attribute(forName: "NAME")?.stringValue == serverName else { continue }
                for data in element.elements(forName: "DATA") {
                    if let home = optionValue(data, name: "CATALINA_HOME"), !home.isEmpty {
                        return home
                    }
                }
            }
        }
        return nil
    }

    private static func optionValue(_ element: XMLElement, name: String) -> String? {
        for child in element.elements(forName: "option") {
            if child.attribute(forName: "name")?.stringValue == name {
                return child.attribute(forName: "value")?.stringValue
            }
        }
        return nil
    }

    private static func sortByModification(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if left != right { return left > right }
            return lhs.path < rhs.path
        }
    }
}
