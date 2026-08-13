import AeroRouteCore
#if os(macOS)
import AppKit
import SwiftUI
#endif
import XCTest
@testable import AeroRoute

final class AeroRouteTests: XCTestCase {
    @MainActor
    func testAirportSearchStoreUsesSubmittedExactCodeContractForAutocomplete() {
        let provider = StubAirportSearchProvider { text, phase, limit in
            XCTAssertEqual(text, "pvg")
            XCTAssertEqual(phase, .submitted)
            XCTAssertEqual(limit, 1)
            return AirportSearchSnapshot(
                text: text,
                presentation: .automaticSelection,
                candidates: [Self.pudongAirport(isExactCodeMatch: true)]
            )
        }
        let store = AirportSearchStore(provider: provider)

        XCTAssertEqual(store.exactCodeMatch("pvg")?.name, "Shanghai Pudong International Airport")
    }

    @MainActor
    func testAirportSearchStoreDoesNotAutocompleteNonCodeAutomaticResult() {
        let provider = StubAirportSearchProvider { text, _, _ in
            AirportSearchSnapshot(
                text: text,
                presentation: .automaticSelection,
                candidates: [Self.pudongAirport(isExactCodeMatch: false)]
            )
        }
        let store = AirportSearchStore(provider: provider)

        XCTAssertNil(store.exactCodeMatch("Shanghai Pudong"))
    }

    @MainActor
    func testAirportSearchStoreAlphabetizesEmptyQueryAirportList() {
        let zurich = AirportSearchCandidate(
            id: 2,
            code: "ZRH",
            name: "Zurich Airport",
            municipality: "Zurich",
            countryCode: "CH",
            countryName: "Switzerland",
            icaoCode: "LSZH",
            isExactCodeMatch: false
        )
        let provider = StubAirportSearchProvider(
            airports: [zurich, Self.pudongAirport(isExactCodeMatch: false)]
        ) { text, _, _ in
            AirportSearchSnapshot(text: text, presentation: .noMatches, candidates: [])
        }
        let store = AirportSearchStore(provider: provider)

        XCTAssertEqual(
            store.airportsAlphabetically().map(\.code),
            ["PVG", "ZRH"]
        )
    }

    @MainActor
    func testAirportSearchEngineAdapterConnectsCoreSearchToPicker() throws {
        let adapter = try AirportSearchEngineAdapter()

        let response = adapter.lookup(text: "pvg", phase: .submitted, limit: 8)

        XCTAssertEqual(response.presentation, .automaticSelection)
        XCTAssertEqual(response.automaticSelection?.code, "PVG")
        XCTAssertEqual(
            response.automaticSelection?.name,
            "Shanghai Pudong International Airport"
        )
        XCTAssertEqual(response.automaticSelection?.isExactCodeMatch, true)
        XCTAssertTrue(response.candidates.allSatisfy { $0.code.count == 3 })
    }

    @MainActor
    func testAirportSearchEngineAdapterDoesNotTreatICAOAsEditableIATACode() throws {
        let adapter = try AirportSearchEngineAdapter()

        let response = adapter.lookup(text: "ZSPD", phase: .submitted, limit: 8)

        XCTAssertEqual(response.automaticSelection?.code, "PVG")
        XCTAssertEqual(response.automaticSelection?.isExactCodeMatch, false)
    }

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
    func testZoomToFlightSettingReframesPreviewAndExport() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([example("sk2596.csv")])
        try await waitForIdle(workspace)
        let worldWidth = abs(
            try XCTUnwrap(workspace.previewStats?.endXY.x)
                - XCTUnwrap(workspace.previewStats?.startXY.x)
        )

        workspace.settings.zoomToFlight = true
        workspace.scheduleRender()
        try await waitForIdle(workspace)

        let focusedWidth = abs(
            try XCTUnwrap(workspace.previewStats?.endXY.x)
                - XCTUnwrap(workspace.previewStats?.startXY.x)
        )
        XCTAssertGreaterThan(focusedWidth, worldWidth * 5)
        XCTAssertTrue(workspace.previewSVG?.contains("data-map-scope=\"flight\"") == true)

        workspace.prepareExport()
        try await waitForIdle(workspace)
        let exportData = try XCTUnwrap(workspace.exportDocument?.data)
        let exportSVG = try XCTUnwrap(String(data: exportData, encoding: .utf8))
        XCTAssertTrue(exportSVG.contains("data-map-scope=\"flight\""))
    }

    @MainActor
    func testAirportLabelsCanBeEditedFromTheirCSVLeg() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([
            example("sk2596.csv"),
            example("lx1279.csv"),
        ])
        try await waitForIdle(workspace)

        let firstLeg = try XCTUnwrap(workspace.legs.first?.id)
        let secondLeg = try XCTUnwrap(workspace.legs.last?.id)
        workspace.updateAirportLabels(
            for: firstLeg,
            origin: AirportLabel(code: "kef", name: "Keflavik"),
            destination: AirportLabel(code: "cph", name: "Copenhagen")
        )
        workspace.updateAirportLabels(
            for: secondLeg,
            origin: AirportLabel(code: "cph", name: "Copenhagen"),
            destination: AirportLabel(code: "zrh", name: "Zurich")
        )
        try await waitForIdle(workspace)

        XCTAssertEqual(workspace.settings.airportCodes, "KEF,CPH,ZRH")
        XCTAssertEqual(workspace.settings.airportNames, "Keflavik,Copenhagen,Zurich")
        XCTAssertEqual(workspace.legSummaries.map(\.origin), ["KEF", "CPH"])
        XCTAssertEqual(workspace.legSummaries.map(\.destination), ["CPH", "ZRH"])
        XCTAssertEqual(workspace.airportLabels(for: secondLeg)?.origin.name, "Copenhagen")
        XCTAssertTrue(workspace.previewSVG?.contains("CPH · Copenhagen") == true)
    }

    @MainActor
    func testAirportLabelEditingPreservesEmptyWaypointPositions() async throws {
        let workspace = RouteWorkspace()
        workspace.importURLs([
            example("sk2596.csv"),
            example("lx1279.csv"),
        ])
        try await waitForIdle(workspace)

        let secondLeg = try XCTUnwrap(workspace.legs.last?.id)
        workspace.updateAirportLabels(
            for: secondLeg,
            origin: .empty,
            destination: AirportLabel(code: "zrh", name: "Zurich")
        )
        try await waitForIdle(workspace)

        XCTAssertEqual(workspace.settings.airportCodes, ",,ZRH")
        XCTAssertEqual(workspace.legSummaries[0].origin, "—")
        XCTAssertEqual(workspace.legSummaries[0].destination, "—")
        XCTAssertEqual(workspace.legSummaries[1].origin, "—")
        XCTAssertEqual(workspace.legSummaries[1].destination, "ZRH")
        XCTAssertTrue(workspace.previewSVG?.contains("ZRH · Zurich") == true)
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
    func testAirportSearchFieldIsPresentInItsContentLayout() throws {
        let hostingView = NSHostingView(
            rootView: AirportSearchField(text: .constant("")) {}
                .frame(width: 500)
                .padding()
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 540, height: 80)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let searchField = try XCTUnwrap(
            descendants(of: hostingView).compactMap { $0 as? NSTextField }.first {
                $0.placeholderString == "Code, airport, city, or country"
            }
        )
        XCTAssertFalse(searchField.isHidden)
        XCTAssertGreaterThan(searchField.frame.width, 300)
        XCTAssertGreaterThan(searchField.frame.height, 0)
    }

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

    private static func pudongAirport(isExactCodeMatch: Bool) -> AirportSearchCandidate {
        AirportSearchCandidate(
            id: 1,
            code: "PVG",
            name: "Shanghai Pudong International Airport",
            municipality: "Shanghai",
            countryCode: "CN",
            countryName: "China",
            icaoCode: "ZSPD",
            isExactCodeMatch: isExactCodeMatch
        )
    }
}

private struct StubAirportSearchProvider: AirportSearchProviding {
    let airports: [AirportSearchCandidate]
    let handler: @MainActor (String, AirportSearchQueryPhase, Int?) -> AirportSearchSnapshot

    init(
        airports: [AirportSearchCandidate] = [],
        handler: @escaping @MainActor (
            String,
            AirportSearchQueryPhase,
            Int?
        ) -> AirportSearchSnapshot
    ) {
        self.airports = airports
        self.handler = handler
    }

    func airportsAlphabetically() -> [AirportSearchCandidate] {
        airports
    }

    func lookup(
        text: String,
        phase: AirportSearchQueryPhase,
        limit: Int?
    ) -> AirportSearchSnapshot {
        handler(text, phase, limit)
    }
}
