import SwiftUI

enum PopoverNoticeKind {
    case success
    case error
}

struct PopoverNotice: Identifiable {
    let id = UUID()
    var kind: PopoverNoticeKind
    var text: String
}

struct PopoverConfirm: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var confirmTitle: String = "Elimina"
    var onConfirm: () -> Void
}

@MainActor
final class PopoverNotices: ObservableObject {
    static let shared = PopoverNotices()
    @Published private(set) var current: PopoverNotice?
    @Published private(set) var confirm: PopoverConfirm?

    func show(_ text: String, kind: PopoverNoticeKind = .success) {
        confirm = nil
        current = PopoverNotice(kind: kind, text: text)
    }

    func showError(_ text: String) {
        show(text, kind: .error)
    }

    func dismiss(_ id: UUID) {
        guard current?.id == id else { return }
        current = nil
    }

    func askConfirm(title: String, detail: String, confirmTitle: String = "Elimina", onConfirm: @escaping () -> Void) {
        current = nil
        confirm = PopoverConfirm(title: title, detail: detail, confirmTitle: confirmTitle, onConfirm: onConfirm)
    }

    func cancelConfirm() {
        confirm = nil
    }

    func performConfirm() {
        guard let confirm else { return }
        self.confirm = nil
        confirm.onConfirm()
    }
}

struct PopoverBanner: View {
    var notice: PopoverNotice
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(notice.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(background.opacity(0.32), lineWidth: 1)
        )
        .accessibilityLabel(notice.text)
        .task(id: notice.id) {
            let ns: UInt64 = notice.kind == .success ? 2_000_000_000 : 4_500_000_000
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var foreground: Color {
        switch notice.kind {
        case .success: return Color(red: 0.62, green: 0.9, blue: 0.68)
        case .error: return Color(red: 1.0, green: 0.72, blue: 0.68)
        }
    }

    private var background: Color {
        switch notice.kind {
        case .success: return .green
        case .error: return .red
        }
    }
}

struct PopoverConfirmCard: View {
    var prompt: PopoverConfirm
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(prompt.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Annulla", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.button, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer(minLength: 0)
                Button(prompt.confirmTitle, action: onConfirm)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.68))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
