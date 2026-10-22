import SwiftUI

struct ResourceStatusDetails: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let status: String
    let details: [String]
}

@MainActor
final class ResourceStatusPopoverCoordinator: ObservableObject {
    @Published private(set) var activeDetails: ResourceStatusDetails?

    private var dismissalTask: Task<Void, Never>?

    func iconHoverChanged(_ isHovering: Bool, details: ResourceStatusDetails) {
        if isHovering {
            dismissalTask?.cancel()
            dismissalTask = nil
            if activeDetails?.id != details.id {
                activeDetails = details
            }
        } else {
            scheduleDismissal(for: details.id)
        }
    }

    func popoverHoverChanged(_ isHovering: Bool, detailsID: String) {
        guard activeDetails?.id == detailsID else { return }
        if isHovering {
            dismissalTask?.cancel()
            dismissalTask = nil
        } else {
            scheduleDismissal(for: detailsID)
        }
    }

    func presentationChanged(_ details: ResourceStatusDetails?, expectedID: String) {
        guard details == nil, activeDetails?.id == expectedID else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        activeDetails = nil
    }

    func presentationBinding(for details: ResourceStatusDetails) -> Binding<ResourceStatusDetails?> {
        Binding(
            get: { self.activeDetails?.id == details.id ? self.activeDetails : nil },
            set: { self.presentationChanged($0, expectedID: details.id) }
        )
    }

    private func scheduleDismissal(for detailsID: String) {
        guard activeDetails?.id == detailsID else { return }
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, self?.activeDetails?.id == detailsID else { return }
            self?.activeDetails = nil
            self?.dismissalTask = nil
        }
    }
}

struct ResourceStatusIcon: View {
    @EnvironmentObject private var popovers: ResourceStatusPopoverCoordinator

    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let status: String
    let details: [String]

    private var statusDetails: ResourceStatusDetails {
        ResourceStatusDetails(id: id, title: title, tint: tint, status: status, details: details)
    }

    var body: some View {
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
            .onHover { popovers.iconHoverChanged($0, details: statusDetails) }
            .popover(
                item: popovers.presentationBinding(for: statusDetails),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) { presentedDetails in
                ResourceStatusPopoverContent(details: presentedDetails)
            }
    }
}

private struct ResourceStatusPopoverContent: View {
    @EnvironmentObject private var popovers: ResourceStatusPopoverCoordinator

    let details: ResourceStatusDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(details.title)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 7) {
                Circle()
                    .fill(details.tint)
                    .frame(width: 8, height: 8)
                Text(details.status)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !details.details.isEmpty {
                Divider()
                ForEach(Array(details.details.enumerated()), id: \.offset) { _, detail in
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
        .onHover { popovers.popoverHoverChanged($0, detailsID: details.id) }
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
