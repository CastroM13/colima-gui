import SwiftUI

extension View {
    @ViewBuilder
    func resourceTableRowBackgroundsDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.alternatingRowBackgrounds(.disabled)
        } else {
            self
        }
    }
}

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
                        .pointingHandCursor()
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
                    .pointingHandCursor()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(30)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .disabled(isDisabled)
        .pointingHandCursor(isEnabled: !isDisabled)
    }
}
