import Foundation

struct ColimaDockerService {
    private let runner: DockerCommandRunner
    private let decoder = JSONDecoder()
    private let colima = CLICommandRunner(name: "colima")

    init(runner: DockerCommandRunner = DockerCommandRunner()) {
        self.runner = runner
    }

    func ensureColimaIsRunning(onStarting: @MainActor () -> Void) async -> ColimaConnectionState {
        do {
            let status = try await colima.run(["status", "--profile", "default"])
            if status.status != 0 {
                await onStarting()
                _ = try await colima.runChecked(["start", "--profile", "default"])
            }
            return await connectionState()
        } catch {
            return .unavailable(message: error.localizedDescription)
        }
    }

    func connectionState() async -> ColimaConnectionState {
        do {
            let version = try await runner.runChecked(["info", "--format", "{{.ServerVersion}}"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty else {
                return .unavailable(message: "Colima is unavailable or returned no server version.")
            }
            return .connected(serverVersion: version)
        } catch {
            return .unavailable(message: connectionMessage(for: error))
        }
    }

    private func connectionMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("context \"colima\"") && normalized.contains("not found") {
            return "The Colima Docker context is missing. Run `colima start` to create it, then refresh."
        }
        if normalized.contains("cannot connect to the docker daemon")
            || normalized.contains("is the docker daemon running")
            || normalized.contains("no such file or directory") {
            return "Colima is not reachable. Start it with `colima start`, then refresh."
        }
        return message
    }

    func loadStacks() async throws -> [StackResource] {
        async let projectOutput = runner.runChecked(["compose", "ls", "--all", "--format", "json"])
        async let containers = fetchContainers()

        let projects = try decoder.decode([ComposeProjectRecord].self, from: Data(try await projectOutput.utf8))
        let allContainers = try await containers
        let grouped = Dictionary(grouping: allContainers.compactMap { container -> (String, ContainerResource)? in
            guard let name = container.projectName else { return nil }
            return (name, container)
        }, by: \.0)

        return projects.map { project in
            let projectContainers = (grouped[project.name] ?? []).map(\.1)
            let workingDirectory = projectContainers
                .compactMap { $0.labels["com.docker.compose.project.working_dir"] }
                .first

            return StackResource(
                id: project.name,
                status: project.status ?? "unknown",
                configFiles: parseConfigFiles(project.configFiles),
                workingDirectory: workingDirectory,
                containers: projectContainers,
                containerCount: projectContainers.count,
                runningContainerCount: projectContainers.filter(\.isRunning).count
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func loadContainers() async throws -> [ContainerResource] {
        try await fetchContainers()
    }

    func loadImages() async throws -> [ImageResource] {
        async let output = runner.runChecked(["image", "ls", "--all", "--no-trunc", "--format", "json"])
        async let containers = fetchContainers()

        let records = try decodeLines(ImageListRecord.self, from: try await output)
        let allContainers = try await containers
        let references = Dictionary(grouping: allContainers, by: { $0.imageID.lowercased() })

        struct Aggregate {
            var repository: String
            var tags: Set<String>
            var size: String
        }

        var aggregates: [String: Aggregate] = [:]
        for record in records {
            let imageID = record.id
            let repository = record.repository == "<none>" ? "<none>" : record.repository
            let tag = record.tag == "<none>" ? nil : record.tag
            if var aggregate = aggregates[imageID] {
                if let tag { aggregate.tags.insert(tag) }
                if aggregate.repository == "<none>", repository != "<none>" {
                    aggregate.repository = repository
                }
                aggregates[imageID] = aggregate
            } else {
                aggregates[imageID] = Aggregate(
                    repository: repository,
                    tags: Set(tag.map { [$0] } ?? []),
                    size: record.size
                )
            }
        }

        let resources: [ImageResource] = aggregates.map { imageID, aggregate in
            ImageResource(
                id: imageID,
                repository: aggregate.repository,
                tags: aggregate.tags.sorted(),
                sizeDescription: aggregate.size,
                containerCount: references[imageID.lowercased()]?.count ?? 0
            )
        }
        return resources.sorted(by: { leftImage, rightImage in
            let leftName = leftImage.tags.first.map { "\(leftImage.repository):\($0)" } ?? leftImage.repository
            let rightName = rightImage.tags.first.map { "\(rightImage.repository):\($0)" } ?? rightImage.repository
            return leftName.localizedStandardCompare(rightName) == .orderedAscending
        })
    }

    func loadVolumes() async throws -> [VolumeResource] {
        async let namesOutput = runner.runChecked(["volume", "ls", "--quiet"])
        async let containers = fetchContainers()

        let names = lines(try await namesOutput)
        let inspections: [VolumeInspection]
        if names.isEmpty {
            inspections = []
        } else {
            let output = try await runner.runChecked(["volume", "inspect"] + names)
            inspections = try decodeArray(VolumeInspection.self, from: output)
        }
        let allContainers = try await containers
        let references = Dictionary(grouping: allContainers.flatMap { container in
            container.mounts.compactMap { mount -> (String, String)? in
                guard mount.type.lowercased() == "volume", let name = mount.volumeName else { return nil }
                return (name, container.name)
            }
        }, by: \.0)

        return inspections.map { volume in
            let projectName = volume.labels?["com.docker.compose.project"]
            return VolumeResource(
                id: volume.name,
                driver: volume.driver,
                labels: volume.labels ?? [:],
                projectName: projectName,
                containerNames: (references[volume.name] ?? []).map(\.1).sorted()
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func loadNetworks() async throws -> [NetworkResource] {
        async let recordsOutput = runner.runChecked(["network", "ls", "--no-trunc", "--format", "json"])
        async let containers = fetchContainers()

        let records = try decodeLines(NetworkListRecord.self, from: try await recordsOutput)
        let inspections: [NetworkInspection]
        if records.isEmpty {
            inspections = []
        } else {
            let output = try await runner.runChecked(["network", "inspect"] + records.map(\.id))
            inspections = try decodeArray(NetworkInspection.self, from: output)
        }
        let allContainers = try await containers
        let referencesByNetworkID = Dictionary(grouping: allContainers.flatMap { container in
            container.networkIDs.map { ($0.lowercased(), container.name) }
        }, by: \.0)
        let referencesByNetworkName = Dictionary(grouping: allContainers.flatMap { container in
            container.networkNames.map { ($0.lowercased(), container.name) }
        }, by: \.0)

        return inspections.map { network in
            let inspectNames = network.containers?.values.map(\.name) ?? []
            let byID = referencesByNetworkID.first { key, _ in
                key == network.id.lowercased() || network.id.lowercased().hasPrefix(key) || key.hasPrefix(network.id.lowercased())
            }?.value.map(\.1) ?? []
            let byName = referencesByNetworkName[network.name.lowercased()]?.map(\.1) ?? []
            let attached = Set(inspectNames + byID + byName).sorted()

            return NetworkResource(
                id: network.id,
                name: network.name,
                driver: network.driver,
                scope: network.scope,
                labels: network.labels ?? [:],
                projectName: network.labels?["com.docker.compose.project"],
                containerNames: attached
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func startStack(_ stack: StackResource) async throws {
        _ = try await runner.runChecked(composeArguments(for: stack, action: "start"))
    }

    func stopStack(_ stack: StackResource) async throws {
        _ = try await runner.runChecked(composeArguments(for: stack, action: "stop"))
    }

    func prepareStackDeletion(_ stack: StackResource) async throws -> StackDeletionPlan {
        async let containersTask = fetchContainers()
        async let volumesTask = loadVolumes()
        async let networksTask = loadNetworks()
        async let externalResourcesTask = loadExternalComposeResources(for: stack)

        let containers = try await containersTask
        let volumes = try await volumesTask
        let networks = try await networksTask
        let externalResources = try? await externalResourcesTask
        let projectContainers = containers.filter { $0.projectName == stack.id }
        let projectContainerNames = Set(projectContainers.map(\.name))

        let projectVolumes = volumes.filter { $0.projectName == stack.id }
        let projectNetworks = networks.filter { $0.projectName == stack.id }
        let removableVolumes = projectVolumes.filter { volume in
            guard let externalResources,
                  !externalResources.volumeNames.contains(volume.id) else { return false }
            return volume.containerNames.allSatisfy { projectContainerNames.contains($0) }
        }
        let blockedVolumes = projectVolumes.filter { volume in
            volume.containerNames.contains { !projectContainerNames.contains($0) }
        }
        let removableNetworks = projectNetworks.filter { network in
            guard let externalResources,
                  !externalResources.networkNames.contains(network.name) else { return false }
            return !network.isBuiltIn && network.containerNames.allSatisfy { projectContainerNames.contains($0) }
        }
        let blockedNetworks = projectNetworks.filter { network in
            network.containerNames.contains { !projectContainerNames.contains($0) }
        }

        return StackDeletionPlan(
            id: stack.id,
            stack: stack,
            containers: projectContainers,
            removableVolumes: removableVolumes,
            removableNetworks: removableNetworks,
            blockedVolumes: blockedVolumes,
            blockedNetworks: blockedNetworks,
            cleanupNotice: externalResources == nil
                ? "Optional network and volume cleanup is unavailable because the current Compose configuration could not be checked."
                : "External Compose networks and volumes are excluded from cleanup."
        )
    }

    func deleteStack(
        _ plan: StackDeletionPlan,
        removingVolumes volumeIDs: Set<String>,
        removingNetworks networkIDs: Set<String>
    ) async throws -> StackDeletionResult {
        let before = try await fetchContainers()
        let currentProjectContainers = before.filter { $0.projectName == plan.id }
        let plannedContainerIDs = Set(plan.containers.map(\.id))
        let currentContainerIDs = Set(currentProjectContainers.map(\.id))
        guard currentContainerIDs == plannedContainerIDs else {
            throw DockerCommandError.invalidOutput("The stack changed after the review was opened. Refresh it and review the deletion again.")
        }

        var issues: [String] = []
        var removedContainerCount = 0
        var containersReadyForRemoval: [ContainerResource] = []
        for container in currentProjectContainers {
            if container.isRunning {
                do {
                    let output = try await runner.run(["container", "stop", container.id])
                    guard output.status == 0 else {
                        issues.append("Could not stop \(container.name); it was kept. \(failureDetail(for: output))")
                        continue
                    }
                } catch {
                    issues.append("Could not stop \(container.name); it was kept. \(error.localizedDescription)")
                    continue
                }
            }
            containersReadyForRemoval.append(container)
        }

        for container in containersReadyForRemoval {
            do {
                let output = try await runner.run(["container", "rm", container.id])
                if output.status == 0 {
                    removedContainerCount += 1
                } else {
                    issues.append("Could not remove \(container.name). \(failureDetail(for: output))")
                }
            } catch {
                issues.append("Could not remove \(container.name). \(error.localizedDescription)")
            }
        }

        var removedVolumes: [String] = []
        if !volumeIDs.isEmpty {
            for volumeID in volumeIDs.sorted() {
                do {
                    let currentExternalResources = try await loadExternalComposeResources(for: plan.stack)
                    guard !currentExternalResources.volumeNames.contains(volumeID) else {
                        issues.append("Kept volume \(volumeID) because the current Compose configuration declares it external.")
                        continue
                    }
                    let currentVolumes = try await loadVolumes()
                    guard plan.removableVolumes.contains(where: { $0.id == volumeID }),
                          let volume = currentVolumes.first(where: { $0.id == volumeID }),
                          volume.projectName == plan.id,
                          volume.containerNames.isEmpty else {
                        issues.append("Kept volume \(volumeID) because it is no longer eligible for cleanup.")
                        continue
                    }
                    let output = try await runner.run(["volume", "rm", volumeID])
                    if output.status == 0 {
                        removedVolumes.append(volumeID)
                    } else {
                        issues.append("Could not remove volume \(volumeID). \(failureDetail(for: output))")
                    }
                } catch {
                    issues.append("Could not verify or remove volume \(volumeID). \(error.localizedDescription)")
                }
            }
        }

        var removedNetworks: [String] = []
        if !networkIDs.isEmpty {
            for networkID in networkIDs.sorted() {
                do {
                    let currentExternalResources = try await loadExternalComposeResources(for: plan.stack)
                    guard let plannedNetwork = plan.removableNetworks.first(where: { $0.id == networkID }),
                          !currentExternalResources.networkNames.contains(plannedNetwork.name) else {
                        issues.append("Kept network \(networkID) because the current Compose configuration declares it external or it is no longer eligible.")
                        continue
                    }
                    let currentNetworks = try await loadNetworks()
                    guard plan.removableNetworks.contains(where: { $0.id == networkID }),
                          let network = currentNetworks.first(where: { $0.id == networkID }),
                          network.projectName == plan.id,
                          !network.isBuiltIn,
                          network.containerNames.isEmpty else {
                        issues.append("Kept network \(networkID) because it is no longer eligible for cleanup.")
                        continue
                    }
                    let output = try await runner.run(["network", "rm", networkID])
                    if output.status == 0 {
                        removedNetworks.append(network.name)
                    } else {
                        issues.append("Could not remove network \(network.name). \(failureDetail(for: output))")
                    }
                } catch {
                    issues.append("Could not verify or remove network \(networkID). \(error.localizedDescription)")
                }
            }
        }

        return StackDeletionResult(
            removedContainerCount: removedContainerCount,
            removedVolumes: removedVolumes,
            removedNetworks: removedNetworks,
            issues: issues
        )
    }

    func startContainer(_ container: ContainerResource) async throws {
        _ = try await runner.runChecked(["container", "start", container.id])
    }

    func stopContainer(_ container: ContainerResource) async throws {
        _ = try await runner.runChecked(["container", "stop", container.id])
    }

    func restartContainer(_ container: ContainerResource) async throws {
        _ = try await runner.runChecked(["container", "restart", container.id])
    }

    func removeContainer(_ container: ContainerResource) async throws {
        guard let current = try await fetchContainers().first(where: { $0.id == container.id }) else {
            throw DockerCommandError.invalidOutput("Container \(container.name) no longer exists. Refresh and try again.")
        }
        if current.isRunning {
            _ = try await runner.runChecked(["container", "stop", current.id])
        }
        _ = try await runner.runChecked(["container", "rm", current.id])
    }

    func removeImage(_ image: ImageResource) async throws {
        let containers = try await fetchContainers()
        let users = containers.filter { $0.imageID.lowercased() == image.id.lowercased() }.map(\.name)
        guard users.isEmpty else {
            throw DockerCommandError.resourceInUse(name: image.id, users: users)
        }
        _ = try await runner.runChecked(["image", "rm", image.id])
    }

    func removeVolume(_ volume: VolumeResource) async throws {
        let current = try await loadVolumes().first(where: { $0.id == volume.id })
        if let current, !current.containerNames.isEmpty {
            throw DockerCommandError.resourceInUse(name: volume.id, users: current.containerNames)
        }
        _ = try await runner.runChecked(["volume", "rm", volume.id])
    }

    func removeNetwork(_ network: NetworkResource) async throws {
        guard !network.isBuiltIn else {
            throw DockerCommandError.unsupportedResource(name: network.name)
        }
        let current = try await loadNetworks().first(where: { $0.id == network.id })
        if let current, !current.containerNames.isEmpty {
            throw DockerCommandError.resourceInUse(name: network.name, users: current.containerNames)
        }
        _ = try await runner.runChecked(["network", "rm", network.id])
    }

    func prune(_ operation: DockerPruneOperation) async throws -> String {
        try await runner.runChecked(operation.arguments)
    }

    private func composeArguments(for stack: StackResource, action: String) throws -> [String] {
        try composeArguments(for: stack, command: [action])
    }

    private func composeArguments(for stack: StackResource, command: [String]) throws -> [String] {
        guard !stack.configFiles.isEmpty else {
            throw DockerCommandError.invalidOutput("No Compose files were recorded for stack \(stack.id).")
        }
        return ["compose", "--project-name", stack.id]
            + stack.configFiles.flatMap { ["--file", $0] }
            + command
    }

    private func loadExternalComposeResources(for stack: StackResource) async throws -> ExternalComposeResources {
        let output = try await runner.runChecked(
            composeArguments(for: stack, command: ["config", "--format", "json"])
        )
        let configuration: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else {
                throw DockerCommandError.invalidOutput("Compose configuration was not a JSON object.")
            }
            configuration = object
        } catch let error as DockerCommandError {
            throw error
        } catch {
            throw DockerCommandError.invalidOutput("Compose configuration was not valid JSON.")
        }

        return ExternalComposeResources(
            volumeNames: externalResourceNames(in: configuration, section: "volumes"),
            networkNames: externalResourceNames(in: configuration, section: "networks")
        )
    }

    private func externalResourceNames(in configuration: [String: Any], section: String) -> Set<String> {
        guard let definitions = configuration[section] as? [String: Any] else { return [] }
        return Set(definitions.compactMap { key, rawDefinition in
            guard let definition = rawDefinition as? [String: Any] else { return nil }
            let externalObject = definition["external"] as? [String: Any]
            let isExternal = (definition["external"] as? Bool == true) || externalObject != nil
            guard isExternal else { return nil }
            return (definition["name"] as? String) ?? (externalObject?["name"] as? String) ?? key
        })
    }

    private func failureDetail(for output: CommandOutput) -> String {
        let detail = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Docker returned exit code \(output.status)." : detail
    }

    private func fetchContainers() async throws -> [ContainerResource] {
        let listOutput = try await runner.runChecked([
            "container", "ls", "--all", "--no-trunc", "--format", "json"
        ])
        let list = try decodeLines(ContainerListRecord.self, from: listOutput)
        guard !list.isEmpty else { return [] }

        let inspectOutput = try await runner.runChecked(["inspect", "--type", "container"] + list.map(\.id))
        let inspected = try decodeArray(ContainerInspection.self, from: inspectOutput)

        return inspected.map { item in
            let id = item.id
            let listEntry = list.first(where: { idsMatch($0.id, id) })
            let name = listEntry?.name ?? item.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let networks = item.networkSettings?.networks ?? [:]
            let mounts = (item.mounts ?? []).map {
                ContainerMount(type: $0.type, volumeName: $0.name, source: $0.source, destination: $0.destination)
            }

            return ContainerResource(
                id: id,
                name: name,
                image: item.config.image,
                imageID: item.image.lowercased(),
                state: item.state.status,
                status: listEntry?.status ?? item.state.status,
                ports: listEntry?.ports ?? "",
                projectName: item.config.labels?["com.docker.compose.project"],
                labels: item.config.labels ?? [:],
                mounts: mounts,
                networkIDs: networks.values.map { $0.networkID.lowercased() }.filter { !$0.isEmpty },
                networkNames: Array(networks.keys)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func decodeArray<T: Decodable>(_ type: T.Type, from output: String) throws -> [T] {
        do {
            return try decoder.decode([T].self, from: Data(output.utf8))
        } catch {
            throw DockerCommandError.invalidOutput(error.localizedDescription)
        }
    }

    private func decodeLines<T: Decodable>(_ type: T.Type, from output: String) throws -> [T] {
        try lines(output).map { line in
            do {
                return try decoder.decode(T.self, from: Data(line.utf8))
            } catch {
                throw DockerCommandError.invalidOutput(error.localizedDescription)
            }
        }
    }

    private func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func parseConfigFiles(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func idsMatch(_ left: String, _ right: String) -> Bool {
        let left = left.lowercased()
        let right = right.lowercased()
        return left == right || left.hasPrefix(right) || right.hasPrefix(left)
    }
}

private struct ExternalComposeResources {
    let volumeNames: Set<String>
    let networkNames: Set<String>
}

private struct ComposeProjectRecord: Decodable {
    let name: String
    let status: String?
    let configFiles: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case status = "Status"
        case configFiles = "ConfigFiles"
    }
}

private struct ContainerListRecord: Decodable {
    let id: String
    let name: String
    let status: String
    let ports: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Names"
        case status = "Status"
        case ports = "Ports"
    }
}

private struct ContainerInspection: Decodable {
    let id: String
    let name: String
    let image: String
    let config: ContainerConfig
    let state: ContainerState
    let mounts: [MountRecord]?
    let networkSettings: NetworkSettings?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case image = "Image"
        case config = "Config"
        case state = "State"
        case mounts = "Mounts"
        case networkSettings = "NetworkSettings"
    }
}

private struct ContainerConfig: Decodable {
    let image: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case image = "Image"
        case labels = "Labels"
    }
}

private struct ContainerState: Decodable {
    let status: String

    enum CodingKeys: String, CodingKey {
        case status = "Status"
    }
}

private struct MountRecord: Decodable {
    let type: String
    let name: String?
    let source: String
    let destination: String

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case name = "Name"
        case source = "Source"
        case destination = "Destination"
    }
}

private struct NetworkSettings: Decodable {
    let networks: [String: NetworkAttachment]?

    enum CodingKeys: String, CodingKey {
        case networks = "Networks"
    }
}

private struct NetworkAttachment: Decodable {
    let networkID: String

    enum CodingKeys: String, CodingKey {
        case networkID = "NetworkID"
    }
}

private struct ImageListRecord: Decodable {
    let id: String
    let repository: String
    let tag: String
    let size: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
    }
}

private struct VolumeInspection: Decodable {
    let name: String
    let driver: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case labels = "Labels"
    }
}

private struct NetworkListRecord: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
    }
}

private struct NetworkInspection: Decodable {
    let id: String
    let name: String
    let driver: String
    let scope: String
    let labels: [String: String]?
    let containers: [String: NetworkEndpoint]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case labels = "Labels"
        case containers = "Containers"
    }
}

private struct NetworkEndpoint: Decodable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}
