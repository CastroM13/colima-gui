import SwiftUI

struct StacksTab: View {
    @EnvironmentObject private var model: ManagerViewModel
    @State private var expandedStackIDs: Set<String> = []

    private var searchQuery: String {
        model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rows: [StackResource] {
        guard !searchQuery.isEmpty else { return model.stacks }
        return model.stacks.filter { stack in
            stack.id.localizedCaseInsensitiveContains(searchQuery)
                || stack.configFiles.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
                || stack.containers.contains { container in
                    container.name.localizedCaseInsensitiveContains(searchQuery)
                        || container.image.localizedCaseInsensitiveContains(searchQuery)
                }
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Stacks",
            isLoading: model.isLoading(.stacks),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.stacks],
            emptyMessage: searchQuery.isEmpty ? "Compose projects will appear here." : "Try a different search.",
            onRefresh: { model.refresh(.stacks) }
        ) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { stack in
                        stackAccordion(stack)
                    }
                }
                .padding(12)
            }
        }
        .onChange(of: searchQuery) { query in
            expandMatchingStacks(for: query)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func stackAccordion(_ stack: StackResource) -> some View {
        let isExpanded = expandedStackIDs.contains(stack.id)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        toggleStack(stack)
                    }
                } label: {
                    stackSummary(stack, isExpanded: isExpanded)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") stack \(stack.id)")
                .accessibilityValue("\(stack.containerCount) containers")

                stackActions(stack)
                    .padding(.trailing, 10)
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                containerList(for: stack)
                    .padding(.leading, 48)
                    .padding(.trailing, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private func stackSummary(_ stack: StackResource, isExpanded: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            ResourceStatusIcon(
                symbol: "square.stack.3d.up",
                tint: ResourceStatusTint.color(for: stack),
                title: stack.id,
                status: stack.status,
                details: [
                    "\(stack.runningContainerCount) running · \(stack.containerCount) total",
                    stack.configFiles.first ?? "Compose file unavailable"
                ]
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(stack.id)
                    .font(.headline)
                Text(stack.configFiles.first ?? "Compose file unavailable")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(stack.configFiles.joined(separator: "\n"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(stack.runningContainerCount) running · \(stack.containerCount) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func containerList(for stack: StackResource) -> some View {
        if stack.containers.isEmpty {
            Text("No containers are attached to this stack.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 6) {
                ForEach(stack.containers) { container in
                    HStack(spacing: 12) {
                        ResourceStatusIcon(
                            symbol: "shippingbox",
                            tint: ResourceStatusTint.color(for: container),
                            title: container.name,
                            status: container.status,
                            details: [
                                "State: \(container.state.capitalized)",
                                "Image: \(container.image)",
                                "Ports: \(container.ports.isEmpty ? "None" : container.ports)"
                            ]
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(container.name)
                                .font(.callout.weight(.medium))
                            Text(container.image)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(container.image)
                        }

                        Spacer(minLength: 12)

                        if !container.ports.isEmpty {
                            Text(container.ports)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                                .help(container.ports)
                        }

                        ContainerActionButtons(container: container, refreshTab: .stacks)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func stackActions(_ stack: StackResource) -> some View {
        HStack(spacing: 4) {
            ResourceActionButton(
                symbol: "play.fill",
                title: "Start stack",
                isDisabled: !model.connectionState.isConnected
                    || model.isBusy("stack", stack.id)
                    || stack.configFiles.isEmpty
                    || (stack.containerCount > 0 && stack.runningContainerCount == stack.containerCount)
            ) { model.startStack(stack) }
            ResourceActionButton(
                symbol: "stop.fill",
                title: "Stop stack",
                isDisabled: !model.connectionState.isConnected
                    || model.isBusy("stack", stack.id)
                    || stack.runningContainerCount == 0
            ) { model.stopStack(stack) }
            ResourceActionButton(
                symbol: "trash",
                title: "Delete stack",
                isDestructive: true,
                isDisabled: !model.connectionState.isConnected || model.isBusy("stack", stack.id)
            ) { model.requestStackDeletion(stack) }
        }
    }

    private func toggleStack(_ stack: StackResource) {
        if expandedStackIDs.contains(stack.id) {
            expandedStackIDs.remove(stack.id)
        } else {
            expandedStackIDs.insert(stack.id)
        }
    }

    private func expandMatchingStacks(for query: String) {
        guard model.selectedTab == .stacks, !query.isEmpty else { return }
        let matchingIDs = model.stacks.filter { stack in
            stack.containers.contains { container in
                container.name.localizedCaseInsensitiveContains(query)
                    || container.image.localizedCaseInsensitiveContains(query)
            }
        }.map(\.id)
        expandedStackIDs.formUnion(matchingIDs)
    }
}
