import SwiftUI

struct VolumesTab: View {
    @EnvironmentObject private var model: ManagerViewModel

    private var rows: [VolumeResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.volumes }
        return model.volumes.filter {
            $0.id.localizedCaseInsensitiveContains(query)
                || $0.driver.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Volumes",
            isLoading: model.isLoading(.volumes),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.volumes],
            emptyMessage: model.searchText.isEmpty ? "Docker volumes will appear here." : "Try a different search.",
            onRefresh: { model.refresh(.volumes) }
        ) {
            Table(rows) {
                TableColumn("Volume") { volume in
                    Text(volume.id).fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(volume.id)
                }
                TableColumn("Driver") { volume in Text(volume.driver) }
                TableColumn("Stack") { volume in
                    Text(volume.projectName ?? "—")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Usage") { volume in
                    Text(volume.containerNames.isEmpty ? "Unused" : volume.containerNames.joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundStyle(volume.containerNames.isEmpty ? Color.secondary : Color.orange)
                        .help(volume.containerNames.joined(separator: ", "))
                }
                TableColumn("Actions") { volume in
                    ResourceActionButton(
                        symbol: "trash",
                        title: volume.containerNames.isEmpty ? "Remove volume" : "Volume is in use",
                        isDestructive: true,
                        isDisabled: !model.connectionState.isConnected
                            || model.isBusy("volume", volume.id)
                            || !volume.containerNames.isEmpty
                    ) { model.requestRemoval(.volume(volume)) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
