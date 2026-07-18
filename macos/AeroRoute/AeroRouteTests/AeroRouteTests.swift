import AeroRouteCore
#if os(macOS)
import AppKit
import SwiftUI
#endif
import XCTest
@testable import AeroRoute

final class AeroRouteTests: XCTestCase {
    func testSVGCanBeRasterizedAsPNG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="20" viewBox="0 0 32 20">
          <rect width="32" height="20" fill="#183143"/>
        </svg>
        """

        let data = try rasterizedPNGData(from: svg)

        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

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

        workspace.prepareExport()
        try await waitForIdle(workspace)

        let exportData = try XCTUnwrap(workspace.exportDocument?.data)
        let exportSVG = try XCTUnwrap(String(data: exportData, encoding: .utf8))
        XCTAssertTrue(workspace.isExporterPresented)
        XCTAssertTrue(exportSVG.contains("width=\"16000\""))
        XCTAssertTrue(exportSVG.contains("KEF–CPH–ZRH–PVG"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AeroRoute-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: output) }
        try exportData.write(to: output, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: output), exportData)
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
    func testDuplicateFilesAreIgnoredWithoutReordering() async throws {
        let workspace = RouteWorkspace()
        let source = example("sk2596.csv")
        workspace.importURLs([source, source])

        try await waitForIdle(workspace)

        XCTAssertEqual(workspace.legs.map(\.flightNumber), ["SK2596"])
        XCTAssertFalse(workspace.isAlertPresented)
    }

    @MainActor
    func testClearCancelsAnImportBeforeAReplacementImport() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([example("lx188.csv")])
        workspace.clear()
        workspace.importURLs([example("sk2596.csv")])

        try await waitForIdle(workspace)

        XCTAssertEqual(workspace.legs.map(\.flightNumber), ["SK2596"])
        XCTAssertFalse(workspace.isImporting)
        XCTAssertFalse(workspace.isRendering)
    }

    @MainActor
    func testAWorkspaceChangeInvalidatesPendingExport() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([example("sk2596.csv")])
        try await waitForIdle(workspace)
        XCTAssertTrue(workspace.canExport)

        workspace.prepareExport()
        XCTAssertTrue(workspace.isExporting)

        workspace.settings.title = "Updated title"
        workspace.scheduleRender()
        try await waitForIdle(workspace)

        XCTAssertFalse(workspace.isExporting)
        XCTAssertFalse(workspace.isExporterPresented)
        XCTAssertNil(workspace.exportDocument)
        XCTAssertTrue(workspace.previewSVG?.contains("Updated title") == true)
    }

    @MainActor
    func testClearResetsAnActiveRender() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([example("sk2596.csv")])
        try await waitForIdle(workspace)

        workspace.settings.title = "Rendering"
        workspace.scheduleRender()
        XCTAssertTrue(workspace.isRendering)

        workspace.clear()

        XCTAssertTrue(workspace.legs.isEmpty)
        XCTAssertFalse(workspace.isImporting)
        XCTAssertFalse(workspace.isRendering)
        XCTAssertFalse(workspace.isExporting)
        XCTAssertNil(workspace.previewSVG)
        XCTAssertEqual(workspace.statusMessage, "No files imported")
    }

#if os(macOS)
    @MainActor
    func testRouteDetailDoesNotClaimAnOversizedFittingWidth() {
        let hostingView = NSHostingView(rootView: RouteDetailView(workspace: RouteWorkspace()))
        let fittingWidth = hostingView.fittingSize.width

        XCTAssertLessThan(
            fittingWidth,
            380,
            "RouteDetailView claims \(fittingWidth) pt and forces split-view sidebars to collapse"
        )
    }

    @MainActor
    func testWorkspaceUsesTheSystemSplitViewWithoutAnAppKitBridge() {
        let hostingController = NSHostingController(
            rootView: ContentView(workspace: RouteWorkspace())
        )
        let window = NSWindow(contentViewController: hostingController)

        for size in [
            NSSize(width: 1_000, height: 700),
            NSSize(width: 1_300, height: 820),
            NSSize(width: 900, height: 600),
        ] {
            window.setContentSize(size)
            window.layoutIfNeeded()
            hostingController.view.layoutSubtreeIfNeeded()

            let verticalSplitViews = descendants(of: hostingController.view)
                .compactMap { $0 as? NSSplitView }
                .filter(\.isVertical)
            let workspaceSplit = verticalSplitViews.max {
                $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
            }
            guard let workspaceSplit else {
                return XCTFail("No vertical workspace NSSplitView after resizing to \(size)")
            }

            let visiblePaneWidths = verticalSplitViews.flatMap { splitView in
                splitView.subviews
                    .filter { !$0.isHidden && $0.bounds.width >= 100 }
                    .map(\.bounds.width)
            }
            XCTAssertGreaterThanOrEqual(
                visiblePaneWidths.min() ?? 0,
                195,
                "A native side column collapsed below its usable width at \(size): \(visiblePaneWidths)"
            )

            let responderTypeNames = responderChain(from: workspaceSplit).map {
                String(reflecting: type(of: $0))
            }
            XCTAssertFalse(
                responderTypeNames.contains { $0.contains("MacWorkspaceSplitViewController") },
                "The workspace must not insert an AppKit split controller inside SwiftUI"
            )

            let splitFrame = workspaceSplit.convert(workspaceSplit.bounds, to: hostingController.view)
            let bottomGap = splitFrame.minY - hostingController.view.bounds.minY
            XCTAssertLessThanOrEqual(
                abs(bottomGap),
                1,
                "Workspace leaves a \(bottomGap) pt bottom gap after resizing to \(size)"
            )
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    private func responderChain(from responder: NSResponder) -> [NSResponder] {
        guard let next = responder.nextResponder else { return [] }
        return [next] + responderChain(from: next)
    }

    @MainActor
    func testSVGPreviewRasterizesVisiblePixelsInProcess() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([example("sq22.csv")])
        try await waitForIdle(workspace)

        let svg = try XCTUnwrap(workspace.previewSVG)
        let image = try XCTUnwrap(macOSSVGPreviewImage(from: svg))
        XCTAssertEqual(image.size, NSSize(width: 1_600, height: 1_000))

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 160,
                pixelsHigh: 100,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 160, height: 100))

        var visibleSampleCount = 0
        for y in stride(from: 0, to: 100, by: 5) {
            for x in stride(from: 0, to: 160, by: 5) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.alphaComponent > 0.01
                    && (color.redComponent < 0.98
                        || color.greenComponent < 0.98
                        || color.blueComponent < 0.98)
                {
                    visibleSampleCount += 1
                }
            }
        }
        XCTAssertGreaterThan(visibleSampleCount, 100)
    }
#endif

    @MainActor
    private func waitForIdle(_ workspace: RouteWorkspace) async throws {
        for _ in 0..<600 {
            if !workspace.isImporting && !workspace.isRendering && !workspace.isExporting {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("workspace did not become idle within 30 seconds")
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
