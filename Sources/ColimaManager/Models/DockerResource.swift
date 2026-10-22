import Foundation

enum ResourceTab: String, CaseIterable, Identifiable {
    case stacks
    case containers
    case images
    case volumes
    case networks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stacks: "Stacks"
        case .containers: "Containers"
        case .images: "Images"
        case .volumes: "Volumes"
        case .networks: "Networks"
        }
    }

    var symbol: String {
        switch self {
        case .stacks: "square.stack.3d.up"
        case .containers: "shippingbox"
        case .images: "cube"
        case .volumes: "externaldrive"
        case .networks: "point.3.connected.trianglepath.dotted"
        }
    }
}

enum DockerPruneOperation: String, CaseIterable {
    case stoppedContainers
    case danglingImages
    case allUnusedImages
    case anonymousVolumes
    case allUnusedVolumes
    case unusedNetworks

    static func operation(for tab: ResourceTab, pruneAll: Bool) -> DockerPruneOperation? {
        switch (tab, pruneAll) {
        case (.containers, false): .stoppedContainers
        case (.images, false): .danglingImages
        case (.images, true): .allUnusedImages
        case (.volumes, false): .anonymousVolumes
        case (.volumes, true): .allUnusedVolumes
        case (.networks, false): .unusedNetworks
        case (.stacks, _), (.containers, true), (.networks, true): nil
        }
    }

    var tab: ResourceTab {
        switch self {
        case .stoppedContainers: .containers
        case .danglingImages, .allUnusedImages: .images
        case .anonymousVolumes, .allUnusedVolumes: .volumes
        case .unusedNetworks: .networks
        }
    }

    var arguments: [String] {
        switch self {
        case .stoppedContainers: ["container", "prune", "--force"]
        case .danglingImages: ["image", "prune", "--force"]
        case .allUnusedImages: ["image", "prune", "--all", "--force"]
        case .anonymousVolumes: ["volume", "prune", "--force"]
        case .allUnusedVolumes: ["volume", "prune", "--all", "--force"]
        case .unusedNetworks: ["network", "prune", "--force"]
        }
    }

    var toolbarTitle: String {
        switch self {
        case .stoppedContainers: "Prune stopped containers"
        case .danglingImages: "Prune dangling images"
        case .allUnusedImages: "Prune all unused images"
        case .anonymousVolumes: "Prune unused anonymous volumes"
        case .allUnusedVolumes: "Prune all unused volumes"
        case .unusedNetworks: "Prune unused networks"
        }
    }

    var confirmationTitle: String { toolbarTitle + "?" }

    var confirmationMessage: String {
        switch self {
        case .stoppedContainers:
            "This removes all stopped containers. Running containers and their attached volumes are kept."
        case .danglingImages:
            "This removes untagged images that are not used by any container. Images referenced by containers are kept."
        case .allUnusedImages:
            "This removes every image not used by a container, including tagged images. Images referenced by containers are kept."
        case .anonymousVolumes:
            "This permanently deletes unused anonymous volumes. Volumes referenced by any container are kept."
        case .allUnusedVolumes:
            "This permanently deletes all unused volumes, including named volumes. Volumes referenced by any container are kept."
        case .unusedNetworks:
            "This removes user-defined networks that are not used by any container. Built-in networks are kept."
        }
    }

    var successMessage: String {
        switch self {
        case .stoppedContainers: "Pruned stopped containers."
        case .danglingImages: "Pruned dangling images."
        case .allUnusedImages: "Pruned all unused images."
        case .anonymousVolumes: "Pruned unused anonymous volumes."
        case .allUnusedVolumes: "Pruned all unused volumes."
        case .unusedNetworks: "Pruned unused networks."
        }
    }
}

enum ColimaConnectionState: Equatable {
    case checking
    case starting
    case connected(serverVersion: String)
    case unavailable(message: String)

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

struct CommandOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let status: Int32
}

enum DockerCommandError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case commandFailed(command: String, message: String)
    case invalidOutput(String)
    case resourceInUse(name: String, users: [String])
    case unsupportedResource(name: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Docker CLI was not found. Install Docker CLI with Colima, then reopen the app."
        case let .launchFailed(message):
            return "Could not start Docker CLI: \(message)"
        case let .commandFailed(command, message):
            let detail = message.isEmpty ? "Docker returned an error." : message
            return "\(command): \(detail)"
        case let .invalidOutput(message):
            return "Docker returned data the app could not read: \(message)"
        case let .resourceInUse(name, users):
            return "\(name) is in use by \(users.joined(separator: ", "))."
        case let .unsupportedResource(name):
            return "\(name) is managed by Docker and cannot be removed here."
        }
    }
}

struct StackResource: Identifiable, Sendable {
    let id: String
    let status: String
    let configFiles: [String]
    let workingDirectory: String?
    let containers: [ContainerResource]
    let containerCount: Int
    let runningContainerCount: Int
}

struct ContainerMount: Sendable {
    let type: String
    let volumeName: String?
    let source: String
    let destination: String
}

struct ContainerResource: Identifiable, Sendable {
    let id: String
    let name: String
    let image: String
    let imageID: String
    let state: String
    let status: String
    let ports: String
    let projectName: String?
    let labels: [String: String]
    let mounts: [ContainerMount]
    let networkIDs: [String]
    let networkNames: [String]

    var isRunning: Bool { state.lowercased() == "running" }
}

struct ImageResource: Identifiable, Sendable {
    let id: String
    let repository: String
    let tags: [String]
    let sizeDescription: String
    let containerCount: Int
}

struct VolumeResource: Identifiable, Sendable {
    let id: String
    let driver: String
    let labels: [String: String]
    let projectName: String?
    let containerNames: [String]
}

struct NetworkResource: Identifiable, Sendable {
    let id: String
    let name: String
    let driver: String
    let scope: String
    let labels: [String: String]
    let projectName: String?
    let containerNames: [String]

    var isBuiltIn: Bool { ["bridge", "host", "none"].contains(name.lowercased()) }
}

struct StackDeletionPlan: Identifiable, Sendable {
    let id: String
    let stack: StackResource
    let containers: [ContainerResource]
    let removableVolumes: [VolumeResource]
    let removableNetworks: [NetworkResource]
    let blockedVolumes: [VolumeResource]
    let blockedNetworks: [NetworkResource]
    let cleanupNotice: String
}

struct StackDeletionResult: Sendable {
    let removedContainerCount: Int
    let removedVolumes: [String]
    let removedNetworks: [String]
    let issues: [String]
}
