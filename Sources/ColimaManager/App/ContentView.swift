import SwiftUI

struct ContentView: View {
    @StateObject private var model = ManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(model: model)
            Divider()

            if let message = model.errorMessage {
                OperationFeedback(message: message, kind: .warning) {
                    model.dismissFeedback()
                }
            } else if let message = model.statusMessage {
                OperationFeedback(message: message, kind: .success) {
                    model.dismissFeedback()
                }
            }

            TabView(selection: $model.selectedTab) {
                StacksTab()
                    .tabItem { Label("Stacks", systemImage: ResourceTab.stacks.symbol) }
                    .tag(ResourceTab.stacks)
                ContainersTab()
                    .tabItem { Label("Containers", systemImage: ResourceTab.containers.symbol) }
                    .tag(ResourceTab.containers)
                ImagesTab()
                    .tabItem { Label("Images", systemImage: ResourceTab.images.symbol) }
                    .tag(ResourceTab.images)
                VolumesTab()
                    .tabItem { Label("Volumes", systemImage: ResourceTab.volumes.symbol) }
                    .tag(ResourceTab.volumes)
                NetworksTab()
                    .tabItem { Label("Networks", systemImage: ResourceTab.networks.symbol) }
                    .tag(ResourceTab.networks)
            }
            .environmentObject(model)
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { model.refreshSelectedTab() }
        .onChange(of: model.selectedTab) { tab in model.refresh(tab) }
        .confirmationDialog(
            model.removeConfirmationTitle(),
            isPresented: $model.isShowingRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { model.confirmRemoval() }
            Button("Cancel", role: .cancel) { model.cancelRemoval() }
        } message: {
            Text(model.removeConfirmationMessage())
        }
        .sheet(item: $model.presentedStackDeletion) { plan in
            StackDeletionSheet(
                plan: plan,
                onCancel: { model.presentedStackDeletion = nil },
                onDelete: { volumes, networks in
                    model.deleteStack(plan, volumeIDs: volumes, networkIDs: networks)
                }
            )
        }
        .navigationTitle(model.selectedTab.title)
    }
}

private struct AppHeader: View {
    @ObservedObject var model: ManagerViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(model.selectedTab.title)
                .font(.title3.weight(.semibold))

            Spacer(minLength: 12)
            if !model.activeOperations.isEmpty {
                ProgressView().controlSize(.small)
                    .help("Docker operation in progress")
            }
            ConnectionBadge(state: model.connectionState)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityLabel("Search \(model.selectedTab.title.lowercased())")
            Button {
                model.refreshSelectedTab()
            } label: {
                if model.isLoading(model.selectedTab) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh \(model.selectedTab.title.lowercased())")
            .disabled(model.isLoading(model.selectedTab))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct ConnectionBadge: View {
    let state: ColimaConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .checking: .gray
        case .connected: .green
        case .unavailable: .red
        }
    }

    private var label: String {
        switch state {
        case .checking: "Checking Colima…"
        case let .connected(version): "Colima · Docker \(version)"
        case .unavailable: "Colima unavailable"
        }
    }

    private var helpText: String {
        if case let .unavailable(message) = state { return message }
        return "Docker commands use the Colima context."
    }
}
