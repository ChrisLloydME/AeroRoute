import CSQLite
import Foundation

public final class AirportSearchEngine: @unchecked Sendable {
    private struct SearchableAirport: Sendable {
        let airport: Airport
        let name: String
        let city: String
        let searchText: String
        let words: Set<String>
    }

    private struct RankedAirport {
        let result: AirportSearchResult
        let typeRank: Int
    }

    private let airports: [SearchableAirport]

    public convenience init() throws {
        try self.init(databaseURL: AirportDatabaseResource.url)
    }

    public init(databaseURL: URL) throws {
        airports = try Self.loadAirports(from: databaseURL)
    }

    public var count: Int { airports.count }

    public func search(_ input: String, limit: Int = 20) -> [AirportSearchResult] {
        guard limit > 0 else { return [] }
        let query = NormalizedAirportQuery(input)
        guard !query.isEmpty else { return [] }

        return airports.compactMap { record -> RankedAirport? in
            guard let result = score(record, for: query) else { return nil }
            return RankedAirport(result: result, typeRank: airportTypeRank(record.airport.type))
        }
        .sorted(by: rankedBefore)
        .prefix(limit)
        .map(\.result)
    }

    private func score(
        _ record: SearchableAirport,
        for query: NormalizedAirportQuery
    ) -> AirportSearchResult? {
        var score = 0
        var reasons: [AirportMatchReason] = []

        if let code = query.possibleCode {
            if record.airport.iataCode == code {
                add(1_400, .exactIATA, score: &score, reasons: &reasons)
            }
            if record.airport.icaoCode == code {
                add(1_380, .exactICAO, score: &score, reasons: &reasons)
            }
        }

        if query.normalized == record.name {
            add(1_200, .exactName, score: &score, reasons: &reasons)
        } else if record.name.hasPrefix(query.normalized + " ") {
            add(950, .namePrefix, score: &score, reasons: &reasons)
        }

        if !record.city.isEmpty {
            if query.normalized == record.city {
                add(1_100, .exactCity, score: &score, reasons: &reasons)
            } else if record.city.hasPrefix(query.normalized + " ") {
                add(900, .cityPrefix, score: &score, reasons: &reasons)
            }
        }

        let matchedTerms = query.tokens.filter { token in
            record.words.contains(token)
                || record.words.contains(where: { $0.hasPrefix(token) })
                || record.searchText.contains(token)
        }
        if !query.tokens.isEmpty, matchedTerms.count == query.tokens.count {
            let exactWordCount = query.tokens.filter(record.words.contains).count
            add(
                650 + exactWordCount * 25 + min(query.tokens.count, 4) * 10,
                .allTerms,
                score: &score,
                reasons: &reasons
            )
        }

        if score == 0 {
            addFuzzyMatches(record, query: query, score: &score, reasons: &reasons)
        }

        guard score > 0 else { return nil }
        if record.airport.hasScheduledService { score += 12 }
        if record.airport.iataCode != nil { score += 6 }
        score += airportTypeRank(record.airport.type)

        return AirportSearchResult(airport: record.airport, score: score, reasons: reasons)
    }

    private func addFuzzyMatches(
        _ record: SearchableAirport,
        query: NormalizedAirportQuery,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        if let code = query.possibleCode {
            let codes = [record.airport.iataCode, record.airport.icaoCode].compactMap { $0 }
            if codes.contains(where: { editDistance(code, $0, limit: 1) <= 1 }) {
                add(560, .fuzzyCode, score: &score, reasons: &reasons)
            }
        }

        guard !query.normalized.isEmpty else { return }
        if fuzzyTextMatch(query.normalized, candidate: record.name) {
            add(520, .fuzzyName, score: &score, reasons: &reasons)
        }
        if !record.city.isEmpty, fuzzyTextMatch(query.normalized, candidate: record.city) {
            add(500, .fuzzyCity, score: &score, reasons: &reasons)
        }
    }

    private func fuzzyTextMatch(_ query: String, candidate: String) -> Bool {
        let queryWords = query.split(separator: " ").map(String.init)
        let candidateWords = candidate.split(separator: " ").map(String.init)
        guard !queryWords.isEmpty else { return false }

        return queryWords.allSatisfy { queryWord in
            let allowed = queryWord.count >= 8 ? 2 : (queryWord.count >= 4 ? 1 : 0)
            return candidateWords.contains { candidateWord in
                candidateWord.hasPrefix(queryWord)
                    || editDistance(queryWord, candidateWord, limit: allowed) <= allowed
            }
        }
    }

    private func rankedBefore(_ lhs: RankedAirport, _ rhs: RankedAirport) -> Bool {
        if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
        if lhs.result.airport.hasScheduledService != rhs.result.airport.hasScheduledService {
            return lhs.result.airport.hasScheduledService
        }
        if lhs.typeRank != rhs.typeRank { return lhs.typeRank > rhs.typeRank }
        if (lhs.result.airport.iataCode != nil) != (rhs.result.airport.iataCode != nil) {
            return lhs.result.airport.iataCode != nil
        }
        if lhs.result.airport.name != rhs.result.airport.name {
            return lhs.result.airport.name < rhs.result.airport.name
        }
        return lhs.result.airport.id < rhs.result.airport.id
    }

    private func add(
        _ points: Int,
        _ reason: AirportMatchReason,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        score += points
        if !reasons.contains(reason) { reasons.append(reason) }
    }

    private func airportTypeRank(_ type: String) -> Int {
        switch type {
        case "large_airport": 4
        case "medium_airport": 3
        case "small_airport": 2
        default: 1
        }
    }

    private static func loadAirports(from url: URL) throws -> [SearchableAirport] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw AirportSearchError("Unable to open airport database: \(message)")
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT a.id, a.ident, a.name, a.normalized_name, a.country_code,
                   a.municipality, a.normalized_city, a.iata_code, a.icao_code,
                   a.latitude, a.longitude, a.airport_type, a.scheduled_service,
                   a.search_text, c.name
            FROM airports AS a
            JOIN countries AS c ON c.code = a.country_code
            ORDER BY a.id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AirportSearchError(
                "Unable to read airport database: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        defer { sqlite3_finalize(statement) }

        var records: [SearchableAirport] = []
        records.reserveCapacity(10_000)
        while sqlite3_step(statement) == SQLITE_ROW {
            let airport = Airport(
                id: Int(sqlite3_column_int64(statement, 0)),
                ident: text(statement, 1) ?? "",
                name: text(statement, 2) ?? "",
                countryCode: text(statement, 4) ?? "",
                municipality: text(statement, 5),
                iataCode: text(statement, 7),
                icaoCode: text(statement, 8),
                latitude: sqlite3_column_double(statement, 9),
                longitude: sqlite3_column_double(statement, 10),
                type: text(statement, 11) ?? "",
                hasScheduledService: sqlite3_column_int(statement, 12) == 1
            )
            let name = text(statement, 3) ?? ""
            let city = text(statement, 6) ?? ""
            let countryName = airportSearchText(text(statement, 14) ?? "")
            let countryCode = airport.countryCode.lowercased()
            let searchText = [
                text(statement, 13) ?? "", countryName, countryCode,
            ].joined(separator: " ")
            records.append(
                SearchableAirport(
                    airport: airport,
                    name: name,
                    city: city,
                    searchText: searchText,
                    words: Set(searchText.split(separator: " ").map(String.init))
                )
            )
        }
        guard sqlite3_errcode(database) == SQLITE_DONE else {
            throw AirportSearchError(
                "Unable to read airport database: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        return records
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}

private func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
    if lhs == rhs { return 0 }
    let left = Array(lhs)
    let right = Array(rhs)
    if abs(left.count - right.count) > limit { return limit + 1 }

    var previous = Array(0...right.count)
    for (leftIndex, leftCharacter) in left.enumerated() {
        var current = [leftIndex + 1]
        var rowMinimum = current[0]
        for (rightIndex, rightCharacter) in right.enumerated() {
            let value = min(
                current[rightIndex] + 1,
                previous[rightIndex + 1] + 1,
                previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
            )
            current.append(value)
            rowMinimum = min(rowMinimum, value)
        }
        if rowMinimum > limit { return limit + 1 }
        previous = current
    }
    return previous[right.count]
}
