import XCTest
@testable import ColimaManager

@MainActor
final class StartupTests: XCTestCase {
    func testOpeningWithStoppedColimaStartsItAndLoadsResources() async throws {
        let fixture = try StartupFixture()
        defer { fixture.cleanup() }
        let model = fixture.makeModel()

        model.refreshSelectedTab()
        try await waitForRefresh(model)

        XCTAssertEqual(model.connectionState, .connected(serverVersion: "27.0"))
        XCTAssertNil(model.tabErrors[.stacks])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.ready.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("loaded").path))
    }

    func testAlreadyRunningColimaDoesNotStartAgain() async throws {
        let fixture = try StartupFixture(running: true)
        defer { fixture.cleanup() }
        let model = fixture.makeModel()

        model.refresh(.containers)
        try await waitForRefresh(model)

        XCTAssertTrue(model.connectionState.isConnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.starts.path))
    }

    func testConcurrentTabRefreshesShareStartup() async throws {
        let fixture = try StartupFixture()
        defer { fixture.cleanup() }
        let model = fixture.makeModel()

        model.refresh(.containers)
        model.refresh(.images)
        try await waitForRefresh(model)

        XCTAssertTrue(model.connectionState.isConnected)
        let starts = try String(contentsOf: fixture.starts)
        XCTAssertEqual(starts, "start\n")
        XCTAssertTrue(model.tabErrors.isEmpty)
    }

    func testFailedStartupShowsErrorAndCanBeRetried() async throws {
        let fixture = try StartupFixture(failStart: true)
        defer { fixture.cleanup() }
        let model = fixture.makeModel()

        model.refresh(.containers)
        try await waitForRefresh(model)
        XCTAssertFalse(model.connectionState.isConnected)
        XCTAssertTrue(model.tabErrors[.containers]?.contains("VM failed to start") == true)

        try FileManager.default.removeItem(at: fixture.failure)
        model.refresh(.containers)
        try await waitForRefresh(model)
        XCTAssertTrue(model.connectionState.isConnected)
        XCTAssertNil(model.tabErrors[.containers])
    }

    private func waitForRefresh(_ model: ManagerViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !model.loadingTabs.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(model.loadingTabs.isEmpty, "Refresh timed out")
    }
}

private struct StartupFixture {
    let directory: URL
    let ready: URL
    let starts: URL
    let failure: URL
    let oldPath: String

    init(running: Bool = false, failStart: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ready = directory.appendingPathComponent("ready")
        starts = directory.appendingPathComponent("starts")
        failure = directory.appendingPathComponent("failure")
        oldPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        if running { try Data().write(to: ready) }
        if failStart { try Data().write(to: failure) }
        let scripts = [
            "colima": """
            [ "$2" = --profile ] && [ "$3" = default ] || exit 2
            case "$1" in
              status) [ -f '\(ready.path)' ] ;;
              start)
                echo start >> '\(starts.path)'
                /bin/sleep 0.1
                if [ -f '\(failure.path)' ]; then echo 'VM failed to start' >&2; exit 1; fi
                /usr/bin/touch '\(ready.path)'
                ;;
              *) exit 2 ;;
            esac
            """,
            "docker": """
            [ "$1" = --context ] && [ "$2" = colima ] || exit 2
            shift 2
            if [ ! -f '\(ready.path)' ]; then echo 'Cannot connect to the Docker daemon' >&2; exit 1; fi
            case "$1" in
              info) echo 27.0 ;;
              container|image) /usr/bin/touch '\(directory.path)/loaded' ;;
              compose) echo '[]' ;;
              *) exit 2 ;;
            esac
            """
        ]
        for (name, script) in scripts {
            let url = directory.appendingPathComponent(name)
            try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        setenv("PATH", directory.path + ":" + oldPath, 1)
    }

    @MainActor
    func makeModel() -> ManagerViewModel {
        ManagerViewModel(service: ColimaDockerService(
            runner: DockerCommandRunner(executableURL: directory.appendingPathComponent("docker"))
        ))
    }

    func cleanup() {
        setenv("PATH", oldPath, 1)
        try? FileManager.default.removeItem(at: directory)
    }
}
