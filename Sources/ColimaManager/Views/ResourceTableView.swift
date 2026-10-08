import SwiftUI

struct ResourceTableFrame<Content: View>: View {
    let title: String
    let isLoading: Bool
    let isEmpty: Bool
    let errorMessage: String?
    let emptyMessage: String
    let onRefresh: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage, !isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage).lineLimit(2)
                    Spacer()
                    Button("Retry", action: onRefresh)
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }

            ZStack {
                content

                if isEmpty, isLoading {
                    ProgressView("Loading \(title.lowercased())…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                } else if isEmpty {
                    EmptyResourceState(
                        title: errorMessage == nil ? "No \(title.lowercased())" : "Couldn’t load \(title.lowercased())",
                        message: errorMessage ?? emptyMessage,
                        buttonTitle: errorMessage == nil ? nil : "Try Again",
                        action: onRefresh
                    )
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct EmptyResourceState: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(30)
    }
}

struct StatusPill: View {
    let title: String
    var isPositive = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isPositive ? Color.green : Color.secondary)
            .background((isPositive ? Color.green : Color.gray).opacity(0.12), in: Capsule())
    }
}

struct ResourceActionButton: View {
    let symbol: String
    let title: String
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .disabled(isDisabled)
    }
}

struct FeedbackNotice: View {
    let message: String
    let isError: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
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
        .foregroundStyle(isError ? Color.orange : Color.green)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background((isError ? Color.orange : Color.green).opacity(0.08))
    }
}
