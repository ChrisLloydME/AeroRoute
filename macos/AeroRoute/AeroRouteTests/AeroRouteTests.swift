import AeroRouteCore
import XCTest
@testable import AeroRoute

final class AeroRouteTests: XCTestCase {
    @MainActor
    func testExampleItineraryRendersAndCanExport() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([
            example("sk2596.csv"),
            example("lx1279.csv"),
            example("lx188.csv"),
        ])
        workspace.settings.title = "KEF–CPH–ZRH–PVG"
        workspace.settings.airportCodes = "KEF,CPH,ZRH,PVG"
        workspace.settings.airportNames = "Keflavik,Copenhagen,Zurich,Shanghai Pudong"
        workspace.scheduleRender()

        try await waitForIdle(workspace)

        XCTAssertEqual(workspace.legs.map(\.flightNumber), ["SK2596", "LX1279", "LX188"])
        XCTAssertEqual(workspace.previewStats?.sourcePoints, 3_773)
        XCTAssertEqual(workspace.previewStats?.curveSegments, 3_772)
        XCTAssertTrue(workspace.connectionDistances.allSatisfy { $0 <= 50 })
        XCTAssertTrue(workspace.previewSVG?.contains("KEF · Keflavik") == true)
        XCTAssertTrue(workspace.canExport)
    }

    @MainActor
    func testDisconnectedLegsExposeExactValidationError() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([
            example("lx188.csv"),
            example("sk2596.csv"),
        ])

        try await waitForIdle(workspace)

        XCTAssertFalse(workspace.canExport)
        XCTAssertTrue(
            workspace.renderError?.hasPrefix(
                "leg 1 does not connect to leg 2: end-to-start distance is "
            ) == true
        )
    }

    @MainActor
    private func waitForIdle(_ workspace: RouteWorkspace) async throws {
        for _ in 0..<600 {
            if !workspace.isImporting && !workspace.isRendering {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("import or rendering did not finish within 30 seconds")
    }

    private func example(_ name: String) -> URL {
        Self.repositoryRoot
            .appendingPathComponent("examples/data", isDirectory: true)
            .appendingPathComponent(name)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
