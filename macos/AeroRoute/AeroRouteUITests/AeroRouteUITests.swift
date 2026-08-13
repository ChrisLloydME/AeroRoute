import XCTest

final class AeroRouteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

#if os(macOS)
    @MainActor
    func testInspectorColorRowContentsAreVerticallyCentered() throws {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["Ocean"]
        let value = app.staticTexts["#B2BAC3"]
        let colorWell = app.descendants(matching: .colorWell).firstMatch

        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(value.exists)
        XCTAssertTrue(colorWell.exists)
        XCTAssertEqual(title.frame.midY, colorWell.frame.midY, accuracy: 1)
        XCTAssertEqual(value.frame.midY, colorWell.frame.midY, accuracy: 1)
    }

    @MainActor
    func testExampleItineraryIsReadyForExport() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            example("sk2596.csv").path,
            example("lx1279.csv").path,
            example("lx188.csv").path,
            "--title", "KEF–CPH–ZRH–PVG",
            "--waypoint-codes", "KEF,CPH,ZRH,PVG",
            "--waypoint-names", "Keflavik,Copenhagen,Zurich,Shanghai Pudong",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["route.preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tables["route.legTable"].exists)
        XCTAssertTrue(app.buttons["route.export"].isEnabled)
        XCTAssertTrue(app.staticTexts["SK2596"].exists)
        XCTAssertTrue(app.staticTexts["LX1279"].exists)
        XCTAssertTrue(app.staticTexts["LX188"].exists)
    }

    @MainActor
    func testAirportMatchingToolbarIsAvailableForSingleCSV() throws {
        let app = XCUIApplication()
        app.launchArguments = [example("sk2596.csv").path]
        app.launch()

        XCTAssertTrue(app.otherElements["route.preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["route.matchAirports"].isEnabled)
    }
#endif

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
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
