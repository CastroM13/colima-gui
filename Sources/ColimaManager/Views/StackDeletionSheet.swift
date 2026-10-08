import SwiftUI

struct StackDeletionSheet: View {
    let plan: StackDeletionPlan
    let onCancel: () -> Void
    let onDelete: (Set<String>, Set<String>) -> Void

    @State private var selectedVolumeIDs: Set<String> = []
    @State private var selectedNetworkIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Delete stack \(plan.stack.id)?")
                    .font(.title3.weight(.semibold))
                Text("This stops running containers, then removes \(plan.containers.count) container(s). Compose files on disk are kept.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !plan.removableNetworks.isEmpty {
                        cleanupSection(
                            title: "Networks",
                            subtitle: "Optional. Only project-owned networks unused outside this stack are listed.",
                            resources: plan.removableNetworks,
                            selection: $selectedNetworkIDs,
                            identifier: \.id,
                            label: \.name
                        )
                    }

                    if !plan.removableVolumes.isEmpty {
                        cleanupSection(
                            title: "Volumes",
                            subtitle: "Optional. Removing a volume permanently deletes its data.",
                            resources: plan.removableVolumes,
                            selection: $selectedVolumeIDs,
                            identifier: \.id,
                            label: \.id
                        )
                    }

                    if !plan.blockedNetworks.isEmpty {
                        blockedSection(
                            title: "Networks kept because they are in use",
                            names: plan.blockedNetworks.map { ($0.name, $0.containerNames) }
                        )
                    }

                    if !plan.blockedVolumes.isEmpty {
                        blockedSection(
                            title: "Volumes kept because they are in use",
                            names: plan.blockedVolumes.map { ($0.id, $0.containerNames) }
                        )
                    }

                    if plan.removableNetworks.isEmpty,
                       plan.removableVolumes.isEmpty,
                       plan.blockedNetworks.isEmpty,
                       plan.blockedVolumes.isEmpty {
                        Text("No project-owned networks or volumes were found for cleanup.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete Stack", role: .destructive) {
                    onDelete(selectedVolumeIDs, selectedNetworkIDs)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .frame(minHeight: 340, maxHeight: 560)
        .onAppear {
            selectedVolumeIDs.removeAll()
            selectedNetworkIDs.removeAll()
        }
    }

    private func cleanupSection<Resource: Identifiable, Label: StringProtocol>(
        title: String,
        subtitle: String,
        resources: [Resource],
        selection: Binding<Set<String>>,
        identifier: KeyPath<Resource, Resource.ID>,
        label: KeyPath<Resource, Label>
    ) -> some View where Resource.ID == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(resources) { resource in
                Toggle(isOn: Binding(
                    get: { selection.wrappedValue.contains(resource[keyPath: identifier]) },
                    set: { isSelected in
                        var ids = selection.wrappedValue
                        if isSelected { ids.insert(resource[keyPath: identifier]) }
                        else { ids.remove(resource[keyPath: identifier]) }
                        selection.wrappedValue = ids
                    }
                )) {
                    Text(String(resource[keyPath: label]))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func blockedSection(title: String, names: [(String, [String])]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(names, id: \.0) { name, containers in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        Text(containers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }
}
