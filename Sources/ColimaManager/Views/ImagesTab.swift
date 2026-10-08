import SwiftUI

struct ImagesTab: View {
    @EnvironmentObject private var model: ManagerViewModel

    private var rows: [ImageResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.images }
        return model.images.filter {
            $0.repository.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ResourceTableFrame(
            title: "Images",
            isLoading: model.isLoading(.images),
            isEmpty: rows.isEmpty,
            errorMessage: model.tabErrors[.images],
            emptyMessage: model.searchText.isEmpty ? "Local images will appear here." : "Try a different search.",
            onRefresh: { model.refresh(.images) }
        ) {
            Table(rows) {
                TableColumn("Repository") { image in
                    Text(image.repository).fontWeight(.medium)
                }
                TableColumn("Tags") { image in
                    Text(image.tags.isEmpty ? "<none>" : image.tags.joined(separator: ", "))
                        .lineLimit(1)
                        .help(image.tags.joined(separator: ", "))
                }
                TableColumn("Image ID") { image in
                    Text(String(image.id.prefix(20)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .help(image.id)
                }
                TableColumn("Size") { image in
                    Text(image.sizeDescription)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Containers") { image in
                    Text(image.containerCount == 0 ? "Unused" : "Used by \(image.containerCount)")
                        .foregroundStyle(image.containerCount == 0 ? Color.secondary : Color.orange)
                }
                TableColumn("Actions") { image in
                    ResourceActionButton(
                        symbol: "trash",
                        title: image.containerCount == 0 ? "Remove image" : "Image is used by a container",
                        isDestructive: true,
                        isDisabled: !model.connectionState.isConnected
                            || model.isBusy("image", image.id)
                            || image.containerCount > 0
                    ) { model.requestRemoval(.image(image)) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
