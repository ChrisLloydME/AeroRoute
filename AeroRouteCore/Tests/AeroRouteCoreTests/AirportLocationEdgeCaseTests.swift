import CSQLite
import Foundation
import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportLocationEdgeCaseTests {
    @Test func coordinateValidityIncludesClosedWorldBounds() {
        #expect(AirportCoordinate(latitude: 90, longitude: 180).isValid)
        #expect(AirportCoordinate(latitude: -90, longitude: -180).isValid)
        #expect(!AirportCoordinate(latitude: 90.000_001, longitude: 0).isValid)
        #expect(!AirportCoordinate(latitude: 0, longitude: -180.000_001).isValid)
        #expect(!AirportCoordinate(latitude: .infinity, longitude: 0).isValid)
        #expect(!AirportCoordinate(latitude: 0, longitude: .nan).isValid)
    }

    @Test func greatCircleRankingHandlesAntimeridianAndPoles() throws {
        let engine = try syntheticLocationEngine()

        let antimeridian = engine.airports(near: .init(
            coordinate: .init(latitude: 0, longitude: -179.9),
            maximumDistanceKM: 500
        ))
        #expect(antimeridian.candidates.first?.airport.iataCode == "EAS")
        #expect(antimeridian.candidates.first?.distanceKM ?? .infinity < 35)

        let northPole = engine.airports(near: .init(
            coordinate: .init(latitude: 90, longitude: 180),
            maximumDistanceKM: 25
        ))
        #expect(northPole.candidates.first?.airport.iataCode == "NOR")
        #expect(northPole.candidates.first?.distanceKM ?? .infinity < 12)
    }

    @Test func narrowResultRadiusCannotHideAnAmbiguousRunnerUp() throws {
        let engine = try syntheticLocationEngine()

        let response = engine.airports(near: .init(
            coordinate: .init(latitude: 10, longitude: 10),
            limit: 1,
            maximumDistanceKM: 0.5
        ))

        #expect(response.candidates.map(\.airport.iataCode) == ["TWA"])
        #expect(response.resolution == .manualSelection)
        #expect(response.automaticSelection == nil)
    }

    @Test func fileResponseIdentifiesTheTrackActuallyAnalyzed() throws {
        let imported = try loadFR24(
            airportLocationExampleDataForEdgeCases.appending(path: "fi217.csv")
        )
        let unrelatedMetadata = FR24Metadata(
            source: URL(fileURLWithPath: "/different/metadata.csv"),
            flightNumber: "OTHER",
            callsign: "OTHER",
            rowCount: imported.track.points.count
        )
        let leg = ImportedLeg(track: imported.track, metadata: unrelatedMetadata)

        let response = try #require(
            AirportSearchEngine().matchAirportFiles([leg]).first
        )

        #expect(response.source == imported.track.source)
        #expect(response.metadata.source == unrelatedMetadata.source)
        #expect(response.match.automaticOrigin?.airport.iataCode == "CPH")
        #expect(response.match.automaticDestination?.airport.iataCode == "KEF")
    }
}

private func syntheticLocationEngine() throws -> AirportSearchEngine {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "airport-location-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }

    var database: OpaquePointer?
    guard sqlite3_open(url.path(percentEncoded: false), &database) == SQLITE_OK,
          let database else {
        throw AirportSearchError("Unable to create synthetic airport database")
    }
    defer { sqlite3_close(database) }

    let sql = """
        CREATE TABLE countries (code TEXT PRIMARY KEY, name TEXT NOT NULL);
        INSERT INTO countries VALUES ('ZZ', 'Test Country');
        CREATE TABLE airports (
            id INTEGER PRIMARY KEY, ident TEXT NOT NULL, name TEXT NOT NULL,
            normalized_name TEXT NOT NULL, country_code TEXT NOT NULL,
            municipality TEXT, normalized_city TEXT NOT NULL, iata_code TEXT,
            icao_code TEXT, latitude REAL NOT NULL, longitude REAL NOT NULL,
            airport_type TEXT NOT NULL, scheduled_service INTEGER NOT NULL,
            keywords TEXT, search_text TEXT NOT NULL
        );
        INSERT INTO airports VALUES
            (1, 'ZZE1', 'East Dateline Airport', 'east dateline airport', 'ZZ',
             'Dateline', 'dateline', 'EAS', 'ZZE1', 0, 179.8,
             'medium_airport', 1, '', 'east dateline airport'),
            (2, 'ZZW1', 'West Test Airport', 'west test airport', 'ZZ',
             'West', 'west', 'WES', 'ZZW1', 0, -170,
             'medium_airport', 1, '', 'west test airport'),
            (3, 'ZZN1', 'North Pole Airport', 'north pole airport', 'ZZ',
             'North', 'north', 'NOR', 'ZZN1', 89.9, 0,
             'medium_airport', 1, '', 'north pole airport'),
            (4, 'ZZT1', 'Twin A Airport', 'twin a airport', 'ZZ',
             'Twins', 'twins', 'TWA', 'ZZT1', 10, 10,
             'medium_airport', 1, '', 'twin a airport'),
            (5, 'ZZT2', 'Twin B Airport', 'twin b airport', 'ZZ',
             'Twins', 'twins', 'TWB', 'ZZT2', 10, 10.01,
             'medium_airport', 1, '', 'twin b airport');
        """
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer { if let errorMessage { sqlite3_free(errorMessage) } }
    guard result == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
        throw AirportSearchError("Unable to seed synthetic database: \(message)")
    }
    return try AirportSearchEngine(databaseURL: url)
}

private let airportLocationExampleDataForEdgeCases: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "examples/data", directoryHint: .isDirectory)
}()
