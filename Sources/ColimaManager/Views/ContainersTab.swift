import SwiftUI

struct ContainersTab: View {
    @EnvironmentObject private var model: ManagerViewModel

    private var rows: [ContainerResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.containers }
        return model.containers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.image.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Containers",
            isLoading: model.isLoading(.containers),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.containers],
            emptyMessage: model.searchText.isEmpty ? "Containers will appear here when Colima has workloads." : "Try a different search.",
            onRefresh: { model.refresh(.containers) }
        ) {
            Table(rows) {
                TableColumn("Container") { container in
                    Text(container.name).fontWeight(.medium)
                }
                TableColumn("State") { container in
                    StatusPill(title: container.status, isPositive: container.isRunning)
                }
                TableColumn("Image") { container in
                    Text(container.image)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(container.image)
                }
                TableColumn("Ports") { container in
                    Text(container.ports.isEmpty ? "—" : container.ports)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .help(container.ports)
                }
                TableColumn("Stack") { container in
                    Text(container.projectName ?? "—")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Actions") { container in
                    HStack(spacing: 8) {
                        ResourceActionButton(
                            symbol: container.isRunning ? "stop.fill" : "play.fill",
                            title: container.isRunning ? "Stop container" : "Start container",
                            isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
                        ) {
                            if container.isRunning { model.stopContainer(container) }
                            else { model.startContainer(container) }
                        }
                        ResourceActionButton(
                            symbol: "arrow.clockwise",
                            title: "Restart container",
                            isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
                        ) { model.restartContainer(container) }
                        ResourceActionButton(
                            symbol: "trash",
                            title: "Remove container",
                            isDestructive: true,
                            isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
                        ) { model.requestRemoval(.container(container)) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
