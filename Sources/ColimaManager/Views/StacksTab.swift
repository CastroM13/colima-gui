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
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func stackAccordion(_ stack: StackResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DisclosureGroup(isExpanded: expansionBinding(for: stack)) {
                containerList(for: stack)
                    .padding(.top, 8)
                    .padding(.leading, 16)
            } label: {
                stackSummary(stack)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stackActions(stack)
                .padding(.top, 4)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private func stackSummary(_ stack: StackResource) -> some View {
        HStack(spacing: 12) {
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

            StatusPill(title: stack.status, isPositive: stack.runningContainerCount > 0)

            Text("\(stack.runningContainerCount) running · \(stack.containerCount) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
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
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

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

                        StatusPill(title: container.status, isPositive: container.isRunning)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func stackActions(_ stack: StackResource) -> some View {
        HStack(spacing: 8) {
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

    private func expansionBinding(for stack: StackResource) -> Binding<Bool> {
        Binding(
            get: {
                let containerMatchesSearch = !searchQuery.isEmpty && stack.containers.contains { container in
                    container.name.localizedCaseInsensitiveContains(searchQuery)
                        || container.image.localizedCaseInsensitiveContains(searchQuery)
                }
                return containerMatchesSearch || expandedStackIDs.contains(stack.id)
            },
            set: { isExpanded in
                if isExpanded {
                    expandedStackIDs.insert(stack.id)
                } else {
                    expandedStackIDs.remove(stack.id)
                }
            }
        )
    }
}
