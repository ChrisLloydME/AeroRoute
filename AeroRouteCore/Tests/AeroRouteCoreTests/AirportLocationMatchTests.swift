import Foundation
import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportLocationMatchTests {
    private static let engine = try! AirportSearchEngine()

    @Test func coordinateLookupReturnsRankedCandidatesAndAutomaticSelection() {
        let request = AirportProximityRequest(
            coordinate: AirportCoordinate(latitude: 31.1434, longitude: 121.805),
            limit: 3
        )

        let response = Self.engine.airports(near: request)

        #expect(response.request == request)
        #expect(response.resolution == .automaticSelection)
        #expect(response.candidates.count == 3)
        #expect(response.candidates.first?.airport.iataCode == "PVG")
        #expect(response.candidates.first?.distanceKM == 0)
        #expect(response.candidates.first?.confidence == .high)
        #expect(response.automaticSelection?.airport.icaoCode == "ZSPD")
    }

    @Test func invalidAndRemoteCoordinatesHaveExplicitResolutions() {
        let invalid = Self.engine.airports(near: .init(
            coordinate: .init(latitude: 91, longitude: 0)
        ))
        #expect(invalid.resolution == .invalidCoordinate)
        #expect(invalid.candidates.isEmpty)

        let remote = Self.engine.airports(near: .init(
            coordinate: .init(latitude: 0, longitude: -140),
            maximumDistanceKM: 10
        ))
        #expect(remote.resolution == .noMatches)
        #expect(remote.candidates.isEmpty)
    }

    @Test func equidistantNearbyAirportsRequireManualSelection() {
        let changi = Self.engine.airports(near: .init(
            coordinate: .init(latitude: 1.35019, longitude: 103.994003),
            limit: 10,
            maximumDistanceKM: 25
        ))
        let commercial = try! #require(
            changi.candidates.first { $0.airport.iataCode == "SIN" }?.airport
        )
        let airBase = try! #require(
            changi.candidates.first { $0.airport.name == "Changi Air Base (East)" }?.airport
        )
        let midpoint = AirportCoordinate(
            latitude: (commercial.latitude + airBase.latitude) / 2,
            longitude: (commercial.longitude + airBase.longitude) / 2
        )

        let response = Self.engine.airports(near: .init(
            coordinate: midpoint,
            limit: 5,
            maximumDistanceKM: 25
        ))

        #expect(response.resolution == .manualSelection)
        #expect(response.automaticSelection == nil)
        #expect(response.candidates.first?.airport.iataCode == "SIN")
    }

    @Test(arguments: airportTrackFixtures)
    func exampleTracksResolveTheirKnownEndpoints(
        filename: String,
        expectedOrigin: String,
        expectedDestination: String
    ) throws {
        let imported = try loadFR24(
            airportLocationExampleData.appending(path: filename)
        )

        let response = Self.engine.matchAirports(for: imported.track)

        #expect(response.origin.candidates.first?.airport.iataCode == expectedOrigin)
        #expect(response.destination.candidates.first?.airport.iataCode == expectedDestination)
        #expect(response.origin.resolution == .automaticSelection)
        #expect(response.destination.resolution == .automaticSelection)
        #expect(response.automaticOrigin?.distanceKM ?? .infinity < 5)
        #expect(response.automaticDestination?.distanceKM ?? .infinity < 5)
        #expect(response.automaticOrigin?.supportingPointCount ?? 0 >= 1)
        #expect(response.automaticDestination?.supportingPointCount ?? 0 >= 1)
    }
}

private let airportTrackFixtures: [(String, String, String)] = [
    ("fi217.csv", "CPH", "KEF"),
    ("lh2440.csv", "MUC", "CPH"),
    ("lh727.csv", "PVG", "MUC"),
    ("lx1279.csv", "CPH", "ZRH"),
    ("lx188.csv", "ZRH", "PVG"),
    ("sk2596.csv", "KEF", "CPH"),
    ("sq22.csv", "SIN", "EWR"),
]

private let airportLocationExampleData: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "examples/data", directoryHint: .isDirectory)
}()
