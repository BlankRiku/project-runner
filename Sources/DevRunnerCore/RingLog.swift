import Foundation

struct LineBuffer: Equatable, Sendable {
    private var pending = ""

    mutating func consume(_ chunk: String) -> [String] {
        pending.append(contentsOf: chunk)
        var lines: [String] = []
        while let range = pending.range(of: "\n", options: .literal) {
            var line = String(pending[..<range.lowerBound])
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            lines.append(line)
            pending = String(pending[range.upperBound...])
        }
        return lines
    }

    mutating func flush() -> [String] {
        guard !pending.isEmpty else { return [] }
        var line = pending
        pending = ""
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        return [line]
    }
}

package struct RingLog: Equatable, Sendable {
    private(set) var lines: [String] = []
    var capacity: Int = 1000

    mutating func append(lines newLines: [String]) {
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    mutating func clear() {
        lines.removeAll()
    }

    package func filtered(query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
