import SwiftUI

struct StacksTab: View {
    @EnvironmentObject private var model: ManagerViewModel

    private var rows: [StackResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.stacks }
        return model.stacks.filter {
            $0.id.localizedCaseInsensitiveContains(query)
                || $0.configFiles.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Stacks",
            isLoading: model.isLoading(.stacks),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.stacks],
            emptyMessage: model.searchText.isEmpty ? "Compose projects will appear here." : "Try a different search.",
            onRefresh: { model.refresh(.stacks) }
        ) {
            Table(rows) {
                TableColumn("Stack") { stack in
                    Text(stack.id).fontWeight(.medium)
                }
                TableColumn("Status") { stack in
                    StatusPill(title: stack.status, isPositive: stack.runningContainerCount > 0)
                }
                TableColumn("Containers") { stack in
                    Text("\(stack.runningContainerCount) running / \(stack.containerCount)")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Compose file") { stack in
                    Text(stack.configFiles.first ?? "Unavailable")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(stack.configFiles.joined(separator: "\n"))
                }
                TableColumn("Actions") { stack in
                    HStack(spacing: 8) {
                        ResourceActionButton(
                            symbol: "play.fill",
                            title: "Start stack",
                            isDisabled: !model.connectionState.isConnected
                                || model.isBusy("stack", stack.id)
                                || stack.configFiles.isEmpty
                                || stack.runningContainerCount == stack.containerCount
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
