import CSQLite
import Foundation

public struct AirportCatalogEntry: Equatable, Identifiable, Sendable {
    public let id: Int
    public let iataCode: String
    public let icaoCode: String?
    public let name: String
    public let municipality: String?
    public let countryCode: String
    public let countryName: String

    public init(
        id: Int,
        iataCode: String,
        icaoCode: String?,
        name: String,
        municipality: String?,
        countryCode: String,
        countryName: String
    ) {
        self.id = id
        self.iataCode = iataCode
        self.icaoCode = icaoCode
        self.name = name
        self.municipality = municipality
        self.countryCode = countryCode
        self.countryName = countryName
    }
}

public enum AirportCatalog {
    public static func airportsAlphabetically() throws -> [AirportCatalogEntry] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            AirportDatabaseResource.url.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { if database != nil { sqlite3_close(database) } }
            throw AirportCatalogError("Unable to open the bundled airport database")
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT
            a.id,
            a.iata_code,
            a.icao_code,
            a.name,
            a.municipality,
            a.country_code,
            c.name
        FROM airports AS a
        JOIN countries AS c ON c.code = a.country_code
        WHERE a.iata_code IS NOT NULL
        ORDER BY a.name COLLATE NOCASE, a.iata_code, a.id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AirportCatalogError("Unable to read the bundled airport database")
        }
        defer { sqlite3_finalize(statement) }

        var airports: [AirportCatalogEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let iataCode = text(statement, column: 1),
                  let name = text(statement, column: 3),
                  let countryCode = text(statement, column: 5),
                  let countryName = text(statement, column: 6) else {
                throw AirportCatalogError("The bundled airport database contains an invalid row")
            }
            airports.append(AirportCatalogEntry(
                id: Int(sqlite3_column_int64(statement, 0)),
                iataCode: iataCode,
                icaoCode: text(statement, column: 2),
                name: name,
                municipality: text(statement, column: 4),
                countryCode: countryCode,
                countryName: countryName
            ))
        }
        return airports
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}

public struct AirportCatalogError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
