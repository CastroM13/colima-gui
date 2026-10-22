import SwiftUI

struct ContentView: View {
    @StateObject private var model = ManagerViewModel()
    @StateObject private var statusPopovers = ResourceStatusPopoverCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            if model.connectionState == .starting {
                ProgressView("Starting Colima…")
                    .padding()
            }

            if let message = model.errorMessage {
                OperationFeedback(message: message, kind: .warning) {
                    model.dismissFeedback()
                }
            } else if let message = model.statusMessage {
                OperationFeedback(message: message, kind: .success) {
                    model.dismissFeedback()
                }
            }

            selectedTabContent
                .environmentObject(model)
                .environmentObject(statusPopovers)
        }
        .background {
            ResourceToolbar(model: model)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { model.refreshSelectedTab() }
        .onChange(of: model.selectedTab) { tab in model.refresh(tab) }
        .confirmationDialog(
            model.removeConfirmationTitle(),
            isPresented: $model.isShowingRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button(model.confirmationActionTitle(), role: .destructive) { model.confirmRemoval() }
                .pointingHandCursor()
            Button("Cancel", role: .cancel) { model.cancelRemoval() }
                .pointingHandCursor()
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
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch model.selectedTab {
        case .stacks: StacksTab()
        case .containers: ContainersTab()
        case .images: ImagesTab()
        case .volumes: VolumesTab()
        case .networks: NetworksTab()
        }
    }
}
