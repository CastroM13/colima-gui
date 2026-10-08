import SwiftUI

struct OperationFeedback: View {
    enum Kind {
        case success
        case warning
    }

    let message: String
    let kind: Kind
    let dismiss: () -> Void

    private var tint: Color { kind == .success ? .green : .orange }
    private var symbol: String { kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(message)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Dismiss message")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08))
    }
}
