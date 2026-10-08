import Foundation

struct DockerCommandRunner {
    private let executableURL: URL?

    init(executableURL: URL? = DockerCommandRunner.findDockerExecutable()) {
        self.executableURL = executableURL
    }

    func run(_ arguments: [String]) async throws -> CommandOutput {
        guard let executableURL else {
            throw DockerCommandError.executableNotFound
        }

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--context", "colima"] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw DockerCommandError.launchFailed(error.localizedDescription)
            }

            let outputTask = Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .utility) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            process.waitUntilExit()
            let outputData = await outputTask.value
            let errorData = await errorTask.value

            guard let standardOutput = String(data: outputData, encoding: .utf8),
                  let standardError = String(data: errorData, encoding: .utf8) else {
                throw DockerCommandError.invalidOutput("output was not UTF-8")
            }

            return CommandOutput(
                standardOutput: standardOutput,
                standardError: standardError,
                status: process.terminationStatus
            )
        }.value
    }

    func runChecked(_ arguments: [String]) async throws -> String {
        let output = try await run(arguments)
        guard output.status == 0 else {
            let command = (["docker", "--context", "colima"] + arguments).joined(separator: " ")
            throw DockerCommandError.commandFailed(
                command: command,
                message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.standardOutput
    }

    private static func findDockerExecutable() -> URL? {
        let fileManager = FileManager.default
        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("docker") }
            ?? []

        let candidates = pathEntries + [
            URL(fileURLWithPath: "/opt/homebrew/bin/docker"),
            URL(fileURLWithPath: "/usr/local/bin/docker"),
            URL(fileURLWithPath: "/usr/bin/docker")
        ]

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
