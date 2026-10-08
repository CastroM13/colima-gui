import SwiftUI

struct ResourceStatusIcon: View {
    let symbol: String
    let tint: Color
    let title: String
    let status: String
    let details: [String]
    var clickTogglesPopover = false

    @State private var isIconHovered = false
    @State private var isPopoverHovered = false
    @State private var isPopoverPresented = false
    @State private var dismissalTask: Task<Void, Never>?

    @ViewBuilder
    var body: some View {
        if clickTogglesPopover {
            statusIcon
                .onTapGesture(perform: togglePopover)
        } else {
            statusIcon
        }
    }

    private var statusIcon: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) status")
            .accessibilityValue(status)
            .accessibilityHint("Hover for status details")
            .onHover(perform: iconHoverChanged)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
                popoverContent
            }
            .onDisappear {
                dismissalTask?.cancel()
            }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !details.isEmpty {
                Divider()
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .onHover(perform: popoverHoverChanged)
    }

    private func iconHoverChanged(_ isHovering: Bool) {
        isIconHovered = isHovering
        if isHovering {
            dismissalTask?.cancel()
            isPopoverPresented = true
        } else {
            scheduleDismissal()
        }
    }

    private func popoverHoverChanged(_ isHovering: Bool) {
        isPopoverHovered = isHovering
        if isHovering {
            dismissalTask?.cancel()
            isPopoverPresented = true
        } else {
            scheduleDismissal()
        }
    }

    private func scheduleDismissal() {
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, !isIconHovered, !isPopoverHovered else { return }
            isPopoverPresented = false
        }
    }

    private func togglePopover() {
        isPopoverPresented.toggle()
    }
}

enum ResourceStatusTint {
    static func color(for container: ContainerResource) -> Color {
        switch container.state.lowercased() {
        case "running": .green
        case "paused", "restarting": .orange
        case "dead", "removing": .red
        default: .secondary
        }
    }

    static func color(for stack: StackResource) -> Color {
        guard stack.containerCount > 0, stack.runningContainerCount > 0 else { return .secondary }
        return stack.runningContainerCount == stack.containerCount ? .green : .orange
    }
}
