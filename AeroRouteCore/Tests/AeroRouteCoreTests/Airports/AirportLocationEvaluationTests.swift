import CSQLite
import Testing
@testable import AeroRouteCore

/// Deterministic corpus evaluation for automatic-selection precision. The
/// sample is rebuilt from every bundled database revision.
@Suite(.serialized)
struct AirportLocationEvaluationTests {
    private struct Seed {
        let iata: String
        let latitude: Double
        let longitude: Double
    }

    private static let engine = try! AirportSearchEngine()
    private static let seeds = try! loadSeeds(limit: 240)

    @Test func scheduledAirportCoordinatesHaveHighRecallAndSafeAutomation() {
        var topOne = 0
        var topThree = 0
        var automatic = 0
        var correctAutomatic = 0

        for seed in Self.seeds {
            let hash = stableLocationOrder(seed.iata)
            let latitudeOffset = hash & 1 == 0 ? 0.006 : -0.006
            let longitudeOffset = hash & 2 == 0 ? 0.006 : -0.006
            let response = Self.engine.airports(near: .init(
                coordinate: .init(
                    latitude: seed.latitude + latitudeOffset,
                    longitude: seed.longitude + longitudeOffset
                ),
                limit: 3,
                maximumDistanceKM: 50
            ))
            let codes = response.candidates.compactMap(\.airport.iataCode)
            if codes.first == seed.iata { topOne += 1 }
            if codes.contains(seed.iata) { topThree += 1 }
            if let selected = response.automaticSelection?.airport.iataCode {
                automatic += 1
                if selected == seed.iata { correctAutomatic += 1 }
            }
        }

        #expect(Self.seeds.count == 240)
        #expect(topOne >= 235, "Perturbed-coordinate Top-1 was \(topOne)/240")
        #expect(topThree >= 238, "Perturbed-coordinate Top-3 was \(topThree)/240")
        #expect(automatic >= 200, "Automatic coverage was \(automatic)/240")
        #expect(
            correctAutomatic == automatic,
            "Automatic precision was \(correctAutomatic)/\(automatic)"
        )
    }

    private static func loadSeeds(limit: Int) throws -> [Seed] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            AirportDatabaseResource.url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw AirportSearchError("Unable to open location evaluation database")
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT iata_code, latitude, longitude
            FROM airports
            WHERE scheduled_service = 1
              AND iata_code IS NOT NULL
              AND airport_type IN ('large_airport', 'medium_airport')
            ORDER BY iata_code
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AirportSearchError("Unable to prepare location evaluation query")
        }
        defer { sqlite3_finalize(statement) }

        var seeds: [Seed] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            seeds.append(Seed(
                iata: String(cString: sqlite3_column_text(statement, 0)),
                latitude: sqlite3_column_double(statement, 1),
                longitude: sqlite3_column_double(statement, 2)
            ))
        }
        return Array(seeds.sorted {
            let lhs = stableLocationOrder($0.iata)
            let rhs = stableLocationOrder($1.iata)
            return lhs == rhs ? $0.iata < $1.iata : lhs < rhs
        }.prefix(limit))
    }
}

private func stableLocationOrder(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { hash, byte in
        (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
}
