import SwiftUI

struct ContainersTab: View {
    @EnvironmentObject private var model: ManagerViewModel
    @State private var sortColumn: ContainerSortColumn = .name
    @State private var sortAscending = true

    private var rows: [ContainerResource] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.containers.filter { container in
            query.isEmpty
                || container.name.localizedCaseInsensitiveContains(query)
                || container.image.localizedCaseInsensitiveContains(query)
                || (container.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }

        return filtered.sorted { left, right in
            let comparison = sortColumn.value(for: left)
                .localizedStandardCompare(sortColumn.value(for: right))
            if comparison == .orderedSame {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
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
            GeometryReader { geometry in
                let tableWidth = max(geometry.size.width - 20, 760)
                let columns = ContainerColumnWidths(totalWidth: tableWidth)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        tableHeader(columns)
                            .padding(.bottom, 4)

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, container in
                            ContainerTableRow(container: container, columns: columns)
                                .background {
                                    if index.isMultiple(of: 2) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.055))
                                    }
                                }
                        }
                    }
                    .frame(minHeight: max(geometry.size.height - 20, 0), alignment: .topLeading)
                    .frame(width: tableWidth)
                    .padding(10)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func tableHeader(_ columns: ContainerColumnWidths) -> some View {
        HStack(spacing: 0) {
            sortableHeader("Container", column: .name, width: columns.name)
            header("Actions", width: columns.actions)
            sortableHeader("Image", column: .image, width: columns.image)
            sortableHeader("Ports", column: .ports, width: columns.ports)
            sortableHeader("Stack", column: .stack, width: columns.stack)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)
        }
    }

    private func header(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(width: width, height: 28)
    }

    private func sortableHeader(
        _ title: String,
        column: ContainerSortColumn,
        width: CGFloat
    ) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.lowercased())")
        .accessibilityLabel("Sort by \(title)")
        .accessibilityValue(sortColumn == column ? (sortAscending ? "Ascending" : "Descending") : "Not sorted")
    }
}

private enum ContainerSortColumn: Equatable {
    case name
    case image
    case ports
    case stack

    func value(for container: ContainerResource) -> String {
        switch self {
        case .name: container.name
        case .image: container.image
        case .ports: container.ports
        case .stack: container.projectName ?? ""
        }
    }
}

private struct ContainerColumnWidths {
    let name: CGFloat
    let actions: CGFloat
    let image: CGFloat
    let ports: CGFloat
    let stack: CGFloat

    init(totalWidth: CGFloat) {
        name = totalWidth * 0.25
        actions = totalWidth * 0.18
        image = totalWidth * 0.19
        ports = totalWidth * 0.25
        stack = totalWidth - name - actions - image - ports
    }
}

private struct ContainerTableRow: View {
    let container: ContainerResource
    let columns: ContainerColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ResourceStatusIcon(
                    symbol: "shippingbox",
                    tint: ResourceStatusTint.color(for: container),
                    title: container.name,
                    status: container.status,
                    details: [
                        "State: \(container.state.capitalized)",
                        "Image: \(container.image)",
                        "Ports: \(container.ports.isEmpty ? "None" : container.ports)"
                    ],
                    clickTogglesPopover: true
                )
                Text(container.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(container.name)
                Spacer(minLength: 0)
            }
            .cellFrame(width: columns.name)

            ContainerActionButtons(container: container, refreshTab: .containers)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cellFrame(width: columns.actions)

            Text(container.image)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(container.image)
                .cellFrame(width: columns.image)

            Text(container.ports.isEmpty ? "—" : container.ports)
                .font(.caption.monospaced())
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .help(container.ports)
                .cellFrame(width: columns.ports)

            Text(container.projectName ?? "—")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .help(container.projectName ?? "")
                .cellFrame(width: columns.stack)
        }
        .frame(height: 42)
        .contentShape(Rectangle())
    }
}

private extension View {
    func cellFrame(width: CGFloat) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(width: width, height: 42)
    }
}
