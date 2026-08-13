import CryptoKit
import Foundation
import XCTest
@testable import AeroRouteCore

final class GoldenCompatibilityTests: XCTestCase {
    private struct Fixture {
        let id: String
        let inputs: [String]
        let golden: String
        let sha256: String
        let points: Int
        let segments: Int
        let options: RenderOptions
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            id: "single-fi217",
            inputs: ["fi217.csv"],
            golden: "flight-fi217.svg",
            sha256: "6a39a5d5520f9d48728fe8d99c4f65dd8ec0cb004a2e6223b0d66b31d3737f33",
            points: 708,
            segments: 707,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "FI217",
                originCode: "CPH",
                destinationCode: "KEF",
                originName: "Copenhagen",
                destinationName: "Keflavik"
            )
        ),
        Fixture(
            id: "single-lh2440",
            inputs: ["lh2440.csv"],
            golden: "flight-lh2440.svg",
            sha256: "dcc5b7a339d385ae5d7d3fd0694b2ce562cf86e4e4919706e01284ed7678b00e",
            points: 443,
            segments: 442,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "LH2440",
                originCode: "MUC",
                destinationCode: "CPH",
                originName: "Munich",
                destinationName: "Copenhagen"
            )
        ),
        Fixture(
            id: "single-lh727",
            inputs: ["lh727.csv"],
            golden: "flight-lh727.svg",
            sha256: "524f0a3ef62b5f54292348ba9c5242b028ac0cb4ebf5743aab393f845b7a0620",
            points: 3_182,
            segments: 3_181,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "LH727",
                originCode: "PVG",
                destinationCode: "MUC",
                originName: "Shanghai Pudong",
                destinationName: "Munich"
            )
        ),
        Fixture(
            id: "single-lx1279",
            inputs: ["lx1279.csv"],
            golden: "flight-lx1279.svg",
            sha256: "61f48fe0f977b27908347ba9a900c92023cf20569bcc73c1f99ac020d3661b19",
            points: 431,
            segments: 430,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "LX1279",
                originCode: "CPH",
                destinationCode: "ZRH",
                originName: "Copenhagen",
                destinationName: "Zurich"
            )
        ),
        Fixture(
            id: "single-lx188",
            inputs: ["lx188.csv"],
            golden: "flight-lx188.svg",
            sha256: "22a658ada8dd48c3ad4637e707017e7b308e9cb401875ac27d0d8483a557d618",
            points: 2_697,
            segments: 2_696,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "LX188",
                originCode: "ZRH",
                destinationCode: "PVG",
                originName: "Zurich",
                destinationName: "Shanghai Pudong"
            )
        ),
        Fixture(
            id: "single-sk2596",
            inputs: ["sk2596.csv"],
            golden: "flight-sk2596.svg",
            sha256: "ca557551fb162ff71aa85793e27c6033f64cc3cbe415dcb77b622d2bc3318b0e",
            points: 645,
            segments: 644,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "SK2596",
                originCode: "KEF",
                destinationCode: "CPH",
                originName: "Keflavik",
                destinationName: "Copenhagen"
            )
        ),
        Fixture(
            id: "single-sq22-antimeridian",
            inputs: ["sq22.csv"],
            golden: "flight-sq22.svg",
            sha256: "f8b91b7304679101cf63784ca28f4561fa4ca2579a36b64fd4f1a74d4c27acb2",
            points: 1_794,
            segments: 1_793,
            options: RenderOptions()
        ),
        Fixture(
            id: "itinerary-kef-cph-zrh-pvg",
            inputs: ["sk2596.csv", "lx1279.csv", "lx188.csv"],
            golden: "itinerary-kef-cph-zrh-pvg.svg",
            sha256: "9fdd489464a3b9baab28a57c48522d1704e58585d85e26517ba3434361cff1b0",
            points: 3_773,
            segments: 3_772,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "KEF–CPH–ZRH–PVG",
                waypointCodes: ["KEF", "CPH", "ZRH", "PVG"],
                waypointNames: ["Keflavik", "Copenhagen", "Zurich", "Shanghai Pudong"],
                metadataDetail: "SK2596 · LX1279 · LX188"
            )
        ),
        Fixture(
            id: "itinerary-pvg-muc-cph-kef",
            inputs: ["lh727.csv", "lh2440.csv", "fi217.csv"],
            golden: "itinerary-pvg-muc-cph-kef.svg",
            sha256: "b40ab26acb2bff4aa8874de4c5074f4cd4a94de4ea87c545f39be8dfa47c1b01",
            points: 4_333,
            segments: 4_332,
            options: RenderOptions(
                scale: 10,
                showAirports: true,
                showFlightNumber: true,
                flightNumber: "PVG–MUC–CPH–KEF",
                waypointCodes: ["PVG", "MUC", "CPH", "KEF"],
                waypointNames: ["Shanghai Pudong", "Munich", "Copenhagen", "Keflavik"],
                metadataDetail: "LH727 · LH2440 · FI213"
            )
        ),
    ]

    @MainActor
    func testAllPythonGoldenSVGsAreByteIdentical() throws {
        for fixture in Self.fixtures {
            try XCTContext.runActivity(named: fixture.id) { _ in
                let expectedURL = Self.goldenDirectory.appendingPathComponent(fixture.golden)
                let expected = try Data(contentsOf: expectedURL)
                XCTAssertEqual(Self.sha256(expected), fixture.sha256, "golden fixture was modified")

                let track = try Self.loadFixtureTrack(fixture)
                let rendered = try SVGRenderer.buildSVG(
                    track: track,
                    options: fixture.options
                )
                let actual = Data(rendered.svg.utf8)

                XCTAssertEqual(rendered.stats.sourcePoints, fixture.points)
                XCTAssertEqual(rendered.stats.curveSegments, fixture.segments)
                XCTAssertEqual(
                    Self.sha256(actual),
                    fixture.sha256,
                    Self.differenceDescription(expected: expected, actual: actual)
                )
                XCTAssertEqual(
                    actual,
                    expected,
                    Self.differenceDescription(expected: expected, actual: actual)
                )
            }
        }
    }

    func testWriteSVGUsesTheSameBytesAsBuildSVG() throws {
        let fixture = Self.fixtures[0]
        let track = try Self.loadFixtureTrack(fixture)
        let built = try SVGRenderer.buildSVG(track: track, options: fixture.options)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("nested/flight.svg")
        defer { try? FileManager.default.removeItem(at: directory) }

        let stats = try SVGRenderer.writeSVG(
            track: track,
            destination: destination,
            options: fixture.options
        )

        XCTAssertEqual(stats, built.stats)
        XCTAssertEqual(try Data(contentsOf: destination), Data(built.svg.utf8))
    }

    func testRouteFittingRenderFillsMapViewport() throws {
        let track = try Self.loadFixtureTrack(Self.fixtures[0])
        let rendered = try SVGRenderer.buildSVG(
            track: track,
            options: RenderOptions(fitMapToRoute: true)
        )
        let viewport = MapViewport(left: 0, top: 0, right: 1_600, bottom: 1_000)

        XCTAssertTrue(rendered.svg.contains("data-map-scope=\"route\""))
        XCTAssertTrue(
            rendered.svg.contains(
                "<rect x=\"0\" y=\"0\" width=\"1600\" height=\"1000\" />"
            )
        )
        XCTAssertGreaterThan(abs(rendered.stats.endXY.x - rendered.stats.startXY.x), 500)
        XCTAssertGreaterThanOrEqual(rendered.stats.startXY.x, viewport.left)
        XCTAssertLessThanOrEqual(rendered.stats.startXY.x, viewport.right)
        XCTAssertGreaterThanOrEqual(rendered.stats.endXY.y, viewport.top)
        XCTAssertLessThanOrEqual(rendered.stats.endXY.y, viewport.bottom)
    }

    func testOrderedXMLSerializationMatchesElementTreeConventions() {
        let root = OrderedXMLNode(
            "svg",
            attributes: [
                ("first", "A&B"),
                ("second", "\"<\t\n\r>"),
            ]
        )
        root.add("title", text: "A&B<C>D")
        root.add("rect", attributes: [("id", "empty")])

        XCTAssertEqual(
            root.serialized() + "\n",
            """
            <svg first="A&amp;B" second="&quot;&lt;&#09;&#10;&#13;&gt;">
              <title>A&amp;B&lt;C&gt;D</title>
              <rect id="empty" />
            </svg>

            """
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var exampleDataDirectory: URL {
        repositoryRoot.appendingPathComponent("examples/data", isDirectory: true)
    }

    private static var goldenDirectory: URL {
        repositoryRoot.appendingPathComponent(
            "compatibility/golden/python",
            isDirectory: true
        )
    }

    private static func loadFixtureTrack(_ fixture: Fixture) throws -> Track {
        let inputs = fixture.inputs.map { exampleDataDirectory.appendingPathComponent($0) }
        if inputs.count == 1 {
            return try loadTrack(inputs[0])
        }
        return try combineTracks(
            paths: inputs,
            sourceName: fixture.options.flightNumber ?? "itinerary",
            validateContinuity: true
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func differenceDescription(expected: Data, actual: Data) -> String {
        let commonCount = min(expected.count, actual.count)
        let difference = (0..<commonCount).first { expected[$0] != actual[$0] }
            ?? commonCount
        let start = max(0, difference - 48)
        let expectedEnd = min(expected.count, difference + 96)
        let actualEnd = min(actual.count, difference + 96)
        let expectedContext = String(decoding: expected[start..<expectedEnd], as: UTF8.self)
        let actualContext = String(decoding: actual[start..<actualEnd], as: UTF8.self)
        return "first byte difference at \(difference); expected bytes=\(expected.count), "
            + "actual bytes=\(actual.count)\nexpected: \(expectedContext)\nactual: \(actualContext)"
    }
}
