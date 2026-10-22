import Foundation

struct CLICommandRunner {
    private let name: String
    private let argumentPrefix: [String]
    private let executableURL: URL?

    init(name: String, argumentPrefix: [String] = [], executableURL: URL?) {
        self.name = name
        self.argumentPrefix = argumentPrefix
        self.executableURL = executableURL
    }

    init(name: String, argumentPrefix: [String] = []) {
        self.init(name: name, argumentPrefix: argumentPrefix, executableURL: Self.findExecutable(name))
    }

    func run(_ arguments: [String]) async throws -> CommandOutput {
        guard let executableURL else {
            throw CLICommandError.executableNotFound(name)
        }

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = argumentPrefix + arguments
            // Finder launches have a minimal PATH; Colima also needs to find Lima and its helpers.
            var environment = ProcessInfo.processInfo.environment
            let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = [executableURL.deletingLastPathComponent().path, inheritedPath,
                                   "/opt/homebrew/bin", "/usr/local/bin"].joined(separator: ":")
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw CLICommandError.launchFailed(name, error.localizedDescription)
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
            let command = ([name] + argumentPrefix + arguments).joined(separator: " ")
            throw DockerCommandError.commandFailed(
                command: command,
                message: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.standardOutput
    }

    private static func findExecutable(_ name: String) -> URL? {
        let fileManager = FileManager.default
        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(name) }
            ?? []

        let candidates = pathEntries + [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct DockerCommandRunner {
    private let runner: CLICommandRunner

    init() {
        runner = CLICommandRunner(name: "docker", argumentPrefix: ["--context", "colima"])
    }

    init(executableURL: URL?) {
        runner = CLICommandRunner(name: "docker", argumentPrefix: ["--context", "colima"], executableURL: executableURL)
    }

    func run(_ arguments: [String]) async throws -> CommandOutput {
        try await runner.run(arguments)
    }

    func runChecked(_ arguments: [String]) async throws -> String {
        try await runner.runChecked(arguments)
    }
}

private enum CLICommandError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            return "The \(name) CLI was not found. Install it, then reopen the app."
        case let .launchFailed(name, message):
            return "Could not start \(name) CLI: \(message)"
        }
    }
}
