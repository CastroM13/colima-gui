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
            stackHeader(stack, isExpanded: isExpanded)

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

    private func stackHeader(_ stack: StackResource, isExpanded: Bool) -> some View {
        HStack(spacing: 0) {
            stackToggleButton(stack, isExpanded: isExpanded) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    ResourceStatusIcon(
                        id: "stack:\(stack.id)",
                        symbol: "square.stack.3d.up",
                        tint: ResourceStatusTint.color(for: stack),
                        title: stack.id,
                        status: stack.status,
                        details: [
                            "\(stack.runningContainerCount) running · \(stack.containerCount) total",
                            stack.configFiles.first ?? "Compose file unavailable"
                        ]
                    )
                }
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }

            VStack(alignment: .leading, spacing: 2) {
                stackToggleButton(stack, isExpanded: isExpanded) {
                    Text(stack.id)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }

                ZStack(alignment: .leading) {
                    stackToggleButton(stack, isExpanded: isExpanded) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 18)
                            .contentShape(Rectangle())
                    }

                    ComposeFilePath(path: stack.configFiles.first)
                        .zIndex(1)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stackToggleButton(stack, isExpanded: isExpanded) {
                Text("\(stack.runningContainerCount) running · \(stack.containerCount) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(minHeight: 58)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }

            stackActions(stack)
                .padding(.trailing, 10)
        }
    }

    private func stackToggleButton<Label: View>(
        _ stack: StackResource,
        isExpanded: Bool,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                toggleStack(stack)
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") stack \(stack.id)")
        .accessibilityValue("\(stack.containerCount) containers")
        .pointingHandCursor()
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
                            id: "stack-container:\(stack.id):\(container.id)",
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

                        PublishedPortLinks(portDescription: container.ports)
                            .frame(minWidth: 40, alignment: .trailing)

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
