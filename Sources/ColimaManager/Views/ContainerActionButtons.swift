import SwiftUI

struct ContainerActionButtons: View {
    @EnvironmentObject private var model: ManagerViewModel

    let container: ContainerResource
    let refreshTab: ResourceTab

    var body: some View {
        HStack(spacing: 4) {
            ResourceActionButton(
                symbol: container.isRunning ? "stop.fill" : "play.fill",
                title: container.isRunning ? "Stop container" : "Start container",
                isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
            ) {
                if container.isRunning {
                    model.stopContainer(container, refreshTab: refreshTab)
                } else {
                    model.startContainer(container, refreshTab: refreshTab)
                }
            }
            ResourceActionButton(
                symbol: "arrow.clockwise",
                title: "Restart container",
                isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
            ) {
                model.restartContainer(container, refreshTab: refreshTab)
            }
            ResourceActionButton(
                symbol: "trash",
                title: "Remove container",
                isDestructive: true,
                isDisabled: !model.connectionState.isConnected || model.isBusy("container", container.id)
            ) {
                model.requestRemoval(.container(container), from: refreshTab)
            }
        }
        .fixedSize()
    }
}
