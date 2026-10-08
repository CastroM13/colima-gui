import SwiftUI

struct NetworksTab: View {
    @EnvironmentObject private var model: ManagerViewModel

    private var rows: [NetworkResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.networks }
        return model.networks.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.driver.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Networks",
            isLoading: model.isLoading(.networks),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.networks],
            emptyMessage: model.searchText.isEmpty ? "Docker networks will appear here." : "Try a different search.",
            onRefresh: { model.refresh(.networks) }
        ) {
            Table(rows) {
                TableColumn("Network") { network in
                    Text(network.name).fontWeight(.medium)
                }
                TableColumn("Driver") { network in Text(network.driver) }
                TableColumn("Scope") { network in
                    Text(network.scope).foregroundStyle(.secondary)
                }
                TableColumn("Stack") { network in
                    Text(network.projectName ?? "—")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Attached containers") { network in
                    Text(network.containerNames.isEmpty ? "Unused" : network.containerNames.joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundStyle(network.containerNames.isEmpty ? Color.secondary : Color.orange)
                        .help(network.containerNames.joined(separator: ", "))
                }
                TableColumn("Actions") { network in
                    let unavailable = network.isBuiltIn || !network.containerNames.isEmpty
                    ResourceActionButton(
                        symbol: "trash",
                        title: network.isBuiltIn ? "Built-in network" : (unavailable ? "Network is in use" : "Remove network"),
                        isDestructive: true,
                        isDisabled: !model.connectionState.isConnected
                            || model.isBusy("network", network.id)
                            || unavailable
                    ) { model.requestRemoval(.network(network)) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
