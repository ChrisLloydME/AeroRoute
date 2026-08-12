import CSQLite
import Foundation

public final class AirportSearchEngine: @unchecked Sendable {
    private struct SearchableAirport: Sendable {
        let airport: Airport
        let name: String
        let city: String
        let country: String
        let aliases: [String]
        let nameWords: Set<String>
        let cityWords: Set<String>
        let countryWords: Set<String>
        let aliasWords: Set<String>
        let compactFields: Set<String>
        let acronyms: Set<String>
    }

    private struct RankedAirport {
        let result: AirportSearchResult
        let typeRank: Int
    }

    private struct TokenEvidence {
        let points: Int
        let reason: AirportMatchReason
    }

    private struct SearchIndexes: Sendable {
        var words: [String: [Int]] = [:]
        var prefixes: [String: [Int]] = [:]
        var codes: [String: [Int]] = [:]
        var acronyms: [String: [Int]] = [:]
        var trigrams: [String: [Int]] = [:]
        var knownCodes: Set<String> = []
    }

    private static let acronymNoise: Set<String> = [
        "airport", "airfield", "and", "at", "de", "international", "of", "regional",
        "the",
    ]
    private static let aliasNoise: Set<String> = [
        "airport", "airfield", "international", "municipal", "regional",
    ]

    private let airports: [SearchableAirport]
    private let indexes: SearchIndexes

    public convenience init() throws {
        try self.init(databaseURL: AirportDatabaseResource.url)
    }

    public init(databaseURL: URL) throws {
        airports = try Self.loadAirports(from: databaseURL)
        indexes = Self.makeIndexes(for: airports)
    }

    public var count: Int { airports.count }

    public func search(_ input: String, limit: Int = 20) -> [AirportSearchResult] {
        guard limit > 0 else { return [] }
        let query = NormalizedAirportQuery(input)
        guard !query.isEmpty else { return [] }

        let permitFuzzyCode = query.fuzzyCodeCandidate.map {
            !indexes.knownCodes.contains($0)
        } ?? false
        let candidates = candidateIndices(for: query, permitFuzzyCode: permitFuzzyCode)
        let ranked = candidates.compactMap { index -> RankedAirport? in
            let record = airports[index]
            guard let result = score(record, for: query, permitFuzzyCode: permitFuzzyCode)
            else { return nil }
            return RankedAirport(result: result, typeRank: airportTypeRank(record.airport.type))
        }
        .sorted(by: rankedBefore)

        guard let first = ranked.first else { return [] }
        let ambiguous = queryIsAmbiguous(ranked, query: query)
        return ranked.prefix(limit).map { candidate in
            let nearTop = first.result.score - candidate.result.score <= 80
            let isAmbiguous = ambiguous && nearTop
            let confidence: AirportSearchConfidence
            if isAmbiguous, candidate.result.confidence > .medium {
                confidence = .medium
            } else {
                confidence = candidate.result.confidence
            }
            return AirportSearchResult(
                airport: candidate.result.airport,
                score: candidate.result.score,
                reasons: candidate.result.reasons,
                confidence: confidence,
                isAmbiguous: isAmbiguous
            )
        }
    }

    private func candidateIndices(
        for query: NormalizedAirportQuery,
        permitFuzzyCode: Bool
    ) -> [Int] {
        var candidates: Set<Int> = []
        for code in query.codeCandidates {
            candidates.formUnion(indexes.codes[code] ?? [])
        }
        if permitFuzzyCode, let code = query.fuzzyCodeCandidate {
            for knownCode in indexes.knownCodes where knownCode.count == code.count {
                if airportEditDistance(code, knownCode, limit: 1) == 1 {
                    candidates.formUnion(indexes.codes[knownCode] ?? [])
                }
            }
        }
        for token in query.significantTokens {
            candidates.formUnion(indexes.words[token] ?? [])
            candidates.formUnion(indexes.prefixes[token] ?? [])
            if token.count >= 4 {
                for trigram in trigrams(token) {
                    candidates.formUnion(indexes.trigrams[trigram] ?? [])
                }
            }
        }
        candidates.formUnion(indexes.acronyms[query.compact] ?? [])
        if query.compact.count >= 5 {
            for trigram in trigrams(query.compact) {
                candidates.formUnion(indexes.trigrams[trigram] ?? [])
            }
        }
        return candidates.sorted()
    }

    private func score(
        _ record: SearchableAirport,
        for query: NormalizedAirportQuery,
        permitFuzzyCode: Bool
    ) -> AirportSearchResult? {
        var score = 0
        var reasons: [AirportMatchReason] = []
        let phrase = query.significantTokens.joined(separator: " ")

        for code in query.codeCandidates {
            if record.airport.iataCode == code {
                add(1_800, .exactIATA, score: &score, reasons: &reasons)
            }
            if record.airport.icaoCode == code {
                add(1_780, .exactICAO, score: &score, reasons: &reasons)
            }
        }

        addPhraseEvidence(record, phrase: phrase, score: &score, reasons: &reasons)
        addAcronymEvidence(record, compact: query.compact, score: &score, reasons: &reasons)
        addTokenEvidence(record, tokens: query.significantTokens, score: &score, reasons: &reasons)

        if score == 0 {
            addFuzzyPhraseEvidence(
                record,
                query: query,
                permitFuzzyCode: permitFuzzyCode,
                score: &score,
                reasons: &reasons
            )
        }

        guard score >= 500 else { return nil }
        if record.airport.hasScheduledService { score += 12 }
        if record.airport.iataCode != nil { score += 6 }
        score += airportTypeRank(record.airport.type)

        return AirportSearchResult(
            airport: record.airport,
            score: score,
            reasons: reasons,
            confidence: confidence(for: score, reasons: reasons)
        )
    }

    private func addPhraseEvidence(
        _ record: SearchableAirport,
        phrase: String,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard !phrase.isEmpty else { return }
        if phrase == record.name {
            add(1_550, .exactName, score: &score, reasons: &reasons)
        } else if record.name.hasPrefix(phrase + " ") {
            add(1_050, .namePrefix, score: &score, reasons: &reasons)
        }

        if !record.city.isEmpty {
            if phrase == record.city {
                add(1_400, .exactCity, score: &score, reasons: &reasons)
            } else if record.city.hasPrefix(phrase + " ") {
                add(980, .cityPrefix, score: &score, reasons: &reasons)
            }
        }

        if record.aliases.contains(phrase) {
            add(1_480, .exactAlias, score: &score, reasons: &reasons)
        } else if record.aliases.contains(where: { $0.hasPrefix(phrase + " ") }) {
            add(1_020, .aliasPrefix, score: &score, reasons: &reasons)
        }

        if queryCompact(phrase).count >= 5, record.compactFields.contains(queryCompact(phrase)) {
            add(1_250, .exactAlias, score: &score, reasons: &reasons)
        }
    }

    private func addAcronymEvidence(
        _ record: SearchableAirport,
        compact: String,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard compact.count >= 2, record.acronyms.contains(compact) else { return }
        add(1_100, .acronym, score: &score, reasons: &reasons)
    }

    private func addTokenEvidence(
        _ record: SearchableAirport,
        tokens: [String],
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard !tokens.isEmpty else { return }
        let evidence = tokens.compactMap { bestTokenEvidence($0, record: record) }
        guard evidence.count == tokens.count else { return }

        add(
            520 + evidence.reduce(0) { $0 + $1.points },
            .allTerms,
            score: &score,
            reasons: &reasons
        )
        for item in evidence where item.reason != .tokenMatch {
            if !reasons.contains(item.reason) { reasons.append(item.reason) }
        }
    }

    private func bestTokenEvidence(_ token: String, record: SearchableAirport) -> TokenEvidence? {
        let lowerIATA = record.airport.iataCode?.lowercased()
        let lowerICAO = record.airport.icaoCode?.lowercased()
        if token == lowerIATA || token == lowerICAO {
            return TokenEvidence(points: 220, reason: .tokenMatch)
        }
        if record.nameWords.contains(token) {
            return TokenEvidence(points: 150, reason: .tokenMatch)
        }
        if record.aliasWords.contains(token) {
            return TokenEvidence(points: 145, reason: .tokenMatch)
        }
        if record.cityWords.contains(token) {
            return TokenEvidence(points: 140, reason: .tokenMatch)
        }
        if token == record.airport.countryCode.lowercased() {
            return TokenEvidence(points: 135, reason: .tokenMatch)
        }
        if record.countryWords.contains(token) {
            return TokenEvidence(points: 110, reason: .tokenMatch)
        }

        if token.count >= 2 {
            if record.nameWords.contains(where: { $0.hasPrefix(token) }) {
                return TokenEvidence(points: 120, reason: .namePrefix)
            }
            if record.aliasWords.contains(where: { $0.hasPrefix(token) }) {
                return TokenEvidence(points: 115, reason: .aliasPrefix)
            }
            if record.cityWords.contains(where: { $0.hasPrefix(token) }) {
                return TokenEvidence(points: 110, reason: .cityPrefix)
            }
        }

        let allowed = allowedTextEdits(for: token)
        guard allowed > 0 else { return nil }
        if record.nameWords.contains(where: {
            airportEditDistance(token, $0, limit: allowed) <= allowed
        }) {
            return TokenEvidence(points: 88, reason: .fuzzyName)
        }
        if record.aliasWords.contains(where: {
            airportEditDistance(token, $0, limit: allowed) <= allowed
        }) {
            return TokenEvidence(points: 84, reason: .fuzzyAlias)
        }
        if record.cityWords.contains(where: {
            airportEditDistance(token, $0, limit: allowed) <= allowed
        }) {
            return TokenEvidence(points: 80, reason: .fuzzyCity)
        }
        return nil
    }

    private func addFuzzyPhraseEvidence(
        _ record: SearchableAirport,
        query: NormalizedAirportQuery,
        permitFuzzyCode: Bool,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        if permitFuzzyCode, let code = query.fuzzyCodeCandidate {
            let codes = [record.airport.iataCode, record.airport.icaoCode].compactMap { $0 }
            if codes.contains(where: {
                $0.count == code.count && airportEditDistance(code, $0, limit: 1) == 1
            }) {
                add(540, .fuzzyCode, score: &score, reasons: &reasons)
            }
        }

        guard query.compact.count >= 5 else { return }
        let similarities = record.compactFields.map { trigramSimilarity(query.compact, $0) }
        guard let similarity = similarities.max(), similarity >= 0.58 else { return }
        add(
            430 + Int(similarity * 180),
            .fuzzyPhrase,
            score: &score,
            reasons: &reasons
        )
    }

    private func queryIsAmbiguous(
        _ ranked: [RankedAirport],
        query: NormalizedAirportQuery
    ) -> Bool {
        guard ranked.count > 1 else { return false }
        let first = ranked[0].result
        let second = ranked[1].result
        if first.reasons.contains(.exactIATA) || first.reasons.contains(.exactICAO) {
            return false
        }
        if first.reasons.contains(.exactCity), second.reasons.contains(.exactCity) {
            return true
        }
        return first.score - second.score <= 30
            && first.confidence == second.confidence
            && query.codeCandidates.isEmpty
    }

    private func confidence(
        for score: Int,
        reasons: [AirportMatchReason]
    ) -> AirportSearchConfidence {
        if reasons.contains(.exactIATA) || reasons.contains(.exactICAO)
            || reasons.contains(.exactName) || reasons.contains(.exactAlias) {
            return .exact
        }
        if reasons.contains(.exactCity) || score >= 1_250 { return .high }
        if score >= 720 { return .medium }
        return .low
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
            SELECT a.id, a.ident, a.name, a.country_code, a.municipality,
                   a.iata_code, a.icao_code, a.latitude, a.longitude,
                   a.airport_type, a.scheduled_service, a.keywords, c.name
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
                countryCode: text(statement, 3) ?? "",
                municipality: text(statement, 4),
                iataCode: text(statement, 5),
                icaoCode: text(statement, 6),
                latitude: sqlite3_column_double(statement, 7),
                longitude: sqlite3_column_double(statement, 8),
                type: text(statement, 9) ?? "",
                hasScheduledService: sqlite3_column_int(statement, 10) == 1
            )
            records.append(makeSearchableAirport(
                airport: airport,
                keywords: text(statement, 11) ?? "",
                countryName: text(statement, 12) ?? ""
            ))
        }
        guard sqlite3_errcode(database) == SQLITE_DONE else {
            throw AirportSearchError(
                "Unable to read airport database: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        return records
    }

    private static func makeSearchableAirport(
        airport: Airport,
        keywords: String,
        countryName: String
    ) -> SearchableAirport {
        let name = airportSearchText(airport.name)
        let city = airportSearchText(airport.municipality ?? "")
        let country = airportSearchText(countryName)
        var aliases = keywords.split(separator: ",").map {
            airportSearchText(String($0))
        }.filter { !$0.isEmpty }

        let nameCore = name.split(separator: " ").map(String.init).filter {
            !aliasNoise.contains($0)
        }.joined(separator: " ")
        if !nameCore.isEmpty, nameCore != name { aliases.append(nameCore) }
        if let parenthesis = airport.municipality?.firstIndex(of: "(") {
            let baseCity = airportSearchText(String(airport.municipality?[..<parenthesis] ?? ""))
            if !baseCity.isEmpty, baseCity != city { aliases.append(baseCity) }
        }
        aliases = Array(Set(aliases)).sorted()

        let nameWords = words(name)
        let cityWords = words(city)
        let countryWords = words(country)
        let aliasWords = Set(aliases.flatMap { words($0) })
        let fields = [name, city, country] + aliases
        let compactFields = Set(fields.map(queryCompact).filter { !$0.isEmpty })
        let acronyms = Set(fields.compactMap(makeAcronym).filter { $0.count >= 2 })

        return SearchableAirport(
            airport: airport,
            name: name,
            city: city,
            country: country,
            aliases: aliases,
            nameWords: nameWords,
            cityWords: cityWords,
            countryWords: countryWords,
            aliasWords: aliasWords,
            compactFields: compactFields,
            acronyms: acronyms
        )
    }

    private static func makeIndexes(for airports: [SearchableAirport]) -> SearchIndexes {
        var indexes = SearchIndexes()
        for (index, record) in airports.enumerated() {
            let allWords = record.nameWords
                .union(record.cityWords)
                .union(record.countryWords)
                .union(record.aliasWords)
            for word in allWords {
                append(index, to: word, in: &indexes.words)
                if word.count >= 2 {
                    let characters = Array(word)
                    for length in 2...characters.count {
                        append(index, to: String(characters.prefix(length)), in: &indexes.prefixes)
                    }
                }
                for trigram in trigrams(word) {
                    append(index, to: trigram, in: &indexes.trigrams)
                }
            }
            for code in [record.airport.iataCode, record.airport.icaoCode].compactMap({ $0 }) {
                indexes.knownCodes.insert(code)
                append(index, to: code, in: &indexes.codes)
            }
            for acronym in record.acronyms {
                append(index, to: acronym, in: &indexes.acronyms)
            }
            for compact in record.compactFields {
                for trigram in trigrams(compact) {
                    append(index, to: trigram, in: &indexes.trigrams)
                }
            }
        }
        return indexes
    }

    private static func append(
        _ index: Int,
        to key: String,
        in dictionary: inout [String: [Int]]
    ) {
        if dictionary[key]?.last != index {
            dictionary[key, default: []].append(index)
        }
    }

    private static func words(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private static func makeAcronym(_ value: String) -> String? {
        let initials = value.split(separator: " ").compactMap { word -> Character? in
            let text = String(word)
            guard !acronymNoise.contains(text) else { return nil }
            return text.first
        }
        return initials.isEmpty ? nil : String(initials)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}

private func queryCompact(_ value: String) -> String {
    value.filter { $0.isASCII && $0.isLetter || $0.isNumber }
}

private func allowedTextEdits(for word: String) -> Int {
    if word.count >= 9 { return 2 }
    if word.count >= 4 { return 1 }
    return 0
}

func airportEditDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
    if lhs == rhs { return 0 }
    let left = Array(lhs)
    let right = Array(rhs)
    if abs(left.count - right.count) > limit { return limit + 1 }

    var matrix = Array(
        repeating: Array(repeating: 0, count: right.count + 1),
        count: left.count + 1
    )
    for index in 0...left.count { matrix[index][0] = index }
    for index in 0...right.count { matrix[0][index] = index }

    for leftIndex in 1...left.count {
        var rowMinimum = limit + 1
        for rightIndex in 1...right.count {
            let substitution = matrix[leftIndex - 1][rightIndex - 1]
                + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1)
            var value = min(
                matrix[leftIndex - 1][rightIndex] + 1,
                matrix[leftIndex][rightIndex - 1] + 1,
                substitution
            )
            if leftIndex > 1, rightIndex > 1,
               left[leftIndex - 1] == right[rightIndex - 2],
               left[leftIndex - 2] == right[rightIndex - 1] {
                value = min(value, matrix[leftIndex - 2][rightIndex - 2] + 1)
            }
            matrix[leftIndex][rightIndex] = value
            rowMinimum = min(rowMinimum, value)
        }
        if rowMinimum > limit { return limit + 1 }
    }
    return matrix[left.count][right.count]
}

private func trigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let left = trigrams(lhs)
    let right = trigrams(rhs)
    guard !left.isEmpty, !right.isEmpty else { return 0 }
    return Double(2 * left.intersection(right).count) / Double(left.count + right.count)
}

private func trigrams(_ value: String) -> Set<String> {
    let characters = Array(value)
    guard characters.count >= 3 else { return [] }
    return Set((0...(characters.count - 3)).map {
        String(characters[$0...($0 + 2)])
    })
}
