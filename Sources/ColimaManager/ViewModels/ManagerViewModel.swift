import SwiftUI

@MainActor
final class ManagerViewModel: ObservableObject {
    @Published var selectedTab: ResourceTab = .stacks
    @Published var searchText = ""
    @Published private(set) var connectionState: ColimaConnectionState = .checking
    @Published private(set) var stacks: [StackResource] = []
    @Published private(set) var containers: [ContainerResource] = []
    @Published private(set) var images: [ImageResource] = []
    @Published private(set) var volumes: [VolumeResource] = []
    @Published private(set) var networks: [NetworkResource] = []
    @Published private(set) var loadingTabs: Set<ResourceTab> = []
    @Published private(set) var activeOperations: Set<String> = []
    @Published private(set) var tabErrors: [ResourceTab: String] = [:]
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var presentedStackDeletion: StackDeletionPlan?
    @Published var removalTarget: RemovalTarget?
    @Published var isShowingRemovalConfirmation = false

    private let service: ColimaDockerService
    private var removalSourceTab: ResourceTab?

    init(service: ColimaDockerService = ColimaDockerService()) {
        self.service = service
    }

    func refreshSelectedTab() {
        refresh(selectedTab)
    }

    func refresh(_ tab: ResourceTab) {
        guard !loadingTabs.contains(tab) else { return }
        loadingTabs.insert(tab)
        tabErrors[tab] = nil

        Task {
            defer { loadingTabs.remove(tab) }
            connectionState = await service.connectionState()
            guard connectionState.isConnected else {
                if case let .unavailable(message) = connectionState {
                    tabErrors[tab] = message
                }
                return
            }

            do {
                switch tab {
                case .stacks:
                    stacks = try await service.loadStacks()
                case .containers:
                    containers = try await service.loadContainers()
                case .images:
                    images = try await service.loadImages()
                case .volumes:
                    volumes = try await service.loadVolumes()
                case .networks:
                    networks = try await service.loadNetworks()
                }
            } catch {
                tabErrors[tab] = error.localizedDescription
            }
        }
    }

    func isLoading(_ tab: ResourceTab) -> Bool {
        loadingTabs.contains(tab)
    }

    func isBusy(_ kind: String, _ id: String) -> Bool {
        activeOperations.contains("\(kind):\(id)")
    }

    func startStack(_ stack: StackResource) {
        perform("stack:\(stack.id)", tab: .stacks) {
            try await self.service.startStack(stack)
            return OperationSummary(message: "Started stack \(stack.id).")
        }
    }

    func stopStack(_ stack: StackResource) {
        perform("stack:\(stack.id)", tab: .stacks) {
            try await self.service.stopStack(stack)
            return OperationSummary(message: "Stopped stack \(stack.id).")
        }
    }

    func requestStackDeletion(_ stack: StackResource) {
        let key = "stack:\(stack.id)"
        guard !activeOperations.contains(key) else { return }
        activeOperations.insert(key)
        statusMessage = nil
        errorMessage = nil

        Task {
            defer { activeOperations.remove(key) }
            do {
                presentedStackDeletion = try await service.prepareStackDeletion(stack)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteStack(_ plan: StackDeletionPlan, volumeIDs: Set<String>, networkIDs: Set<String>) {
        presentedStackDeletion = nil
        perform("stack:\(plan.id)", tab: .stacks) {
            let result = try await self.service.deleteStack(
                plan,
                removingVolumes: volumeIDs,
                removingNetworks: networkIDs
            )
            var details = ["Removed \(result.removedContainerCount) container(s) from \(plan.id)"]
            if !result.removedVolumes.isEmpty {
                details.append("\(result.removedVolumes.count) volume(s)")
            }
            if !result.removedNetworks.isEmpty {
                details.append("\(result.removedNetworks.count) network(s)")
            }
            let message = details.joined(separator: "; ") + "."
            if result.issues.isEmpty {
                return OperationSummary(message: message)
            }
            return OperationSummary(message: message + " " + result.issues.joined(separator: " "), warning: true)
        }
    }

    func startContainer(_ container: ContainerResource, refreshTab: ResourceTab = .containers) {
        perform("container:\(container.id)", tab: refreshTab) {
            try await self.service.startContainer(container)
            return OperationSummary(message: "Started \(container.name).")
        }
    }

    func stopContainer(_ container: ContainerResource, refreshTab: ResourceTab = .containers) {
        perform("container:\(container.id)", tab: refreshTab) {
            try await self.service.stopContainer(container)
            return OperationSummary(message: "Stopped \(container.name).")
        }
    }

    func restartContainer(_ container: ContainerResource, refreshTab: ResourceTab = .containers) {
        perform("container:\(container.id)", tab: refreshTab) {
            try await self.service.restartContainer(container)
            return OperationSummary(message: "Restarted \(container.name).")
        }
    }

    func requestRemoval(_ target: RemovalTarget, from sourceTab: ResourceTab? = nil) {
        removalTarget = target
        removalSourceTab = sourceTab
        isShowingRemovalConfirmation = true
        statusMessage = nil
        errorMessage = nil
    }

    func cancelRemoval() {
        isShowingRemovalConfirmation = false
        removalTarget = nil
        removalSourceTab = nil
    }

    func confirmRemoval() {
        guard let target = removalTarget else { return }
        isShowingRemovalConfirmation = false
        removalTarget = nil
        let sourceTab = removalSourceTab
        removalSourceTab = nil

        switch target {
        case let .container(container):
            perform("container:\(container.id)", tab: sourceTab ?? .containers) {
                try await self.service.removeContainer(container)
                return OperationSummary(message: "Removed \(container.name); attached volumes were kept.")
            }
        case let .image(image):
            perform("image:\(image.id)", tab: .images) {
                try await self.service.removeImage(image)
                return OperationSummary(message: "Removed image \(image.repository).")
            }
        case let .volume(volume):
            perform("volume:\(volume.id)", tab: .volumes) {
                try await self.service.removeVolume(volume)
                return OperationSummary(message: "Removed volume \(volume.id).")
            }
        case let .network(network):
            perform("network:\(network.id)", tab: .networks) {
                try await self.service.removeNetwork(network)
                return OperationSummary(message: "Removed network \(network.name).")
            }
        }
    }

    func removeConfirmationTitle() -> String {
        switch removalTarget {
        case .container: "Remove container?"
        case .image: "Remove image?"
        case .volume: "Remove volume?"
        case .network: "Remove network?"
        case nil: "Remove resource?"
        }
    }

    func removeConfirmationMessage() -> String {
        switch removalTarget {
        case let .container(container):
            let action = container.isRunning
                ? "Docker will stop it using its configured grace period and may force-terminate it if that period expires, then remove it."
                : "It will be removed."
            return "Remove \(container.name)? \(action) Attached volumes will be kept."
        case let .image(image):
            return "Remove \(image.repository) \(image.tags.joined(separator: ", "))? Images used by containers cannot be force-removed."
        case let .volume(volume):
            return "Remove volume \(volume.id)? This permanently deletes its data."
        case let .network(network):
            return "Remove network \(network.name)? It must be unused by all containers."
        case nil:
            return ""
        }
    }

    func dismissFeedback() {
        statusMessage = nil
        errorMessage = nil
    }

    private func perform(
        _ key: String,
        tab: ResourceTab,
        operation: @escaping () async throws -> OperationSummary
    ) {
        guard !activeOperations.contains(key) else { return }
        activeOperations.insert(key)
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let summary = try await operation()
                if summary.warning {
                    errorMessage = summary.message
                } else {
                    statusMessage = summary.message
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            activeOperations.remove(key)
            refresh(tab)
        }
    }
}

struct OperationSummary {
    let message: String
    var warning = false
}

enum RemovalTarget: Identifiable {
    case container(ContainerResource)
    case image(ImageResource)
    case volume(VolumeResource)
    case network(NetworkResource)

    var id: String {
        switch self {
        case let .container(value): "container:\(value.id)"
        case let .image(value): "image:\(value.id)"
        case let .volume(value): "volume:\(value.id)"
        case let .network(value): "network:\(value.id)"
        }
    }
}
