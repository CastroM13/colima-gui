import SwiftUI

struct ContainersTab: View {
    @EnvironmentObject private var model: ManagerViewModel
    @State private var sortOrder: [KeyPathComparator<ContainerResource>] = [
        KeyPathComparator(\.name, order: .forward)
    ]

    private var rows: [ContainerResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.containers.filter { container in
            query.isEmpty
                || container.name.localizedCaseInsensitiveContains(query)
                || container.image.localizedCaseInsensitiveContains(query)
                || (container.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }

        return filtered.sorted(using: sortOrder)
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
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Container", value: \.name) { container in
                    HStack(spacing: 8) {
                        ResourceStatusIcon(
                            id: "container:\(container.id)",
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
                        Text(container.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(container.name)
                    }
                }

                TableColumn("Image", value: \.image) { container in
                    Text(container.image)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(container.image)
                }

                TableColumn("Ports", value: \.ports) { container in
                    PublishedPortLinks(portDescription: container.ports)
                }

                TableColumn("Stack", value: \.projectNameForSorting) { container in
                    Text(container.projectName ?? "—")
                        .foregroundStyle(.secondary)
                }

                TableColumn("Actions") { container in
                    ContainerActionButtons(container: container, refreshTab: .containers)
                }
                .width(112)
            }
            .resourceTableRowBackgroundsDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private extension ContainerResource {
    var projectNameForSorting: String { projectName ?? "" }
}
