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

enum ColimaConnectionState: Equatable {
    case checking
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
}

struct StackDeletionResult: Sendable {
    let removedContainerCount: Int
    let removedVolumes: [String]
    let removedNetworks: [String]
    let issues: [String]
}
