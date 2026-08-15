import CSQLite
import Foundation
import Testing
@testable import AeroRouteCore

/// Deterministic corpus-level evaluation. Unlike hand-picked regressions, these
/// cases are re-selected from every bundled database revision.
@Suite(.serialized)
struct AirportSearchEvaluationTests {
    private struct Seed {
        let iata: String
        let icao: String
        let country: String
        let term: String
    }

    private static let engine = try! AirportSearchEngine()
    private static let seeds = try! loadSeeds(limit: 120)

    @Test func exactCodesAreTopOneAcrossTheCorpus() {
        var evaluated = 0
        for seed in Self.seeds {
            let iataResults = Self.engine.search(seed.iata, limit: 3)
            let icaoResults = Self.engine.search(seed.icao, limit: 3)
            #expect(
                iataResults.first?.airport.iataCode == seed.iata,
                "\(seed.iata) returned \(Self.describe(iataResults))"
            )
            #expect(
                icaoResults.first?.airport.iataCode == seed.iata,
                "\(seed.icao) returned \(Self.describe(icaoResults))"
            )
            evaluated += 2
        }
        #expect(evaluated >= 200)
    }

    @Test func distinctiveEnglishTermsHaveHighTopOneRecall() {
        var topOne = 0
        for seed in Self.seeds {
            if Self.engine.search(seed.term, limit: 1).first?.airport.iataCode == seed.iata {
                topOne += 1
            }
        }

        let recall = Double(topOne) / Double(Self.seeds.count)
        #expect(
            recall >= 0.97,
            "Distinctive-term Top-1 recall was \(topOne)/\(Self.seeds.count)"
        )
    }

    @Test func generatedSingleEditTyposHaveHighTopThreeRecall() {
        var evaluated = 0
        var topOne = 0
        var topThree = 0

        for seed in Self.seeds {
            for query in typoVariants(of: seed.term) {
                let codes = Self.engine.search(query, limit: 3).compactMap(\.airport.iataCode)
                evaluated += 1
                if codes.first == seed.iata { topOne += 1 }
                if codes.contains(seed.iata) { topThree += 1 }
            }
        }

        let topOneRecall = Double(topOne) / Double(evaluated)
        let topThreeRecall = Double(topThree) / Double(evaluated)
        #expect(
            topOneRecall >= 0.90,
            "Generated-typo Top-1 recall was \(topOne)/\(evaluated)"
        )
        #expect(
            topThreeRecall >= 0.96,
            "Generated-typo Top-3 recall was \(topThree)/\(evaluated)"
        )
    }

    @Test func distinctivePrefixesRemainVisibleWhileTyping() {
        var visible = 0
        for seed in Self.seeds {
            let length = min(6, max(4, seed.term.utf8.count - 1))
            let prefix = String(seed.term.prefix(length))
            if Self.engine.suggestions(for: prefix, limit: 8).contains(where: {
                $0.airport.iataCode == seed.iata
            }) {
                visible += 1
            }
        }

        let recall = Double(visible) / Double(Self.seeds.count)
        #expect(
            recall >= 0.92,
            "Incremental Top-8 recall was \(visible)/\(Self.seeds.count)"
        )
    }

    @Test func deterministicNonsenseCorpusDoesNotProduceResults() {
        let queries = (0..<64).map { index in
            "qzxv\(String(index, radix: 36))vzxq"
        }
        let rejected = queries.filter { Self.engine.search($0).isEmpty }.count
        #expect(rejected == queries.count, "Nonsense rejection was \(rejected)/\(queries.count)")
    }

    private static func loadSeeds(limit: Int) throws -> [Seed] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            AirportDatabaseResource.url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw AirportSearchError("Unable to open evaluation database")
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT iata_code, icao_code, country_code, name, municipality, keywords
            FROM airports
            WHERE scheduled_service = 1
              AND iata_code IS NOT NULL
              AND icao_code IS NOT NULL
              AND airport_type IN ('large_airport', 'medium_airport')
            ORDER BY country_code, iata_code
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AirportSearchError("Unable to prepare evaluation query")
        }
        defer { sqlite3_finalize(statement) }

        struct Record {
            let iata: String
            let icao: String
            let country: String
            let terms: Set<String>
        }
        var records: [Record] = []
        var documentFrequency: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let values = (3...5).compactMap { column -> String? in
                guard let bytes = sqlite3_column_text(statement, Int32(column)) else { return nil }
                return String(cString: bytes)
            }
            let terms = Set(values.flatMap { value in
                airportSearchText(value).split(separator: " ").map(String.init)
            }.filter(isEvaluationTerm))
            guard !terms.isEmpty else { continue }
            let record = Record(
                iata: sqliteText(statement, 0),
                icao: sqliteText(statement, 1),
                country: sqliteText(statement, 2),
                terms: terms
            )
            records.append(record)
            for term in terms { documentFrequency[term, default: 0] += 1 }
        }

        let candidates = records.compactMap { record -> Seed? in
            let uniqueTerms = record.terms.filter { documentFrequency[$0] == 1 }
            guard let term = uniqueTerms.sorted(by: evaluationTermBefore).first else { return nil }
            return Seed(
                iata: record.iata,
                icao: record.icao,
                country: record.country,
                term: term
            )
        }.sorted {
            let lhs = stableEvaluationOrder($0.iata)
            let rhs = stableEvaluationOrder($1.iata)
            return lhs == rhs ? $0.iata < $1.iata : lhs < rhs
        }

        var selected: [Seed] = []
        var perCountry: [String: Int] = [:]
        for candidate in candidates where selected.count < limit {
            guard perCountry[candidate.country, default: 0] < 2 else { continue }
            selected.append(candidate)
            perCountry[candidate.country, default: 0] += 1
        }
        return selected
    }

    private static func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }

    private static func describe(_ results: [AirportSearchResult]) -> String {
        results.map {
            "\($0.airport.iataCode ?? "-"):\($0.score):\($0.reasons.map(\.rawValue))"
        }.joined(separator: ", ")
    }
}

private let evaluationNoise: Set<String> = [
    "airport", "airfield", "base", "international", "municipal", "regional",
]

private func isEvaluationTerm(_ term: String) -> Bool {
    (5...11).contains(term.utf8.count)
        && !evaluationNoise.contains(term)
        && term.utf8.allSatisfy { byte in
            byte >= Character("a").asciiValue! && byte <= Character("z").asciiValue!
        }
}

private func evaluationTermBefore(_ lhs: String, _ rhs: String) -> Bool {
    if lhs.utf8.count != rhs.utf8.count { return lhs.utf8.count > rhs.utf8.count }
    return lhs < rhs
}

private func stableEvaluationOrder(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { hash, byte in
        (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
}

private func typoVariants(of value: String) -> [String] {
    var bytes = Array(value.utf8)
    guard bytes.count >= 5 else { return [] }
    let middle = bytes.count / 2
    var variants: [String] = []

    var deletion = bytes
    deletion.remove(at: middle)
    variants.append(String(decoding: deletion, as: UTF8.self))

    if middle + 1 < bytes.count, bytes[middle] != bytes[middle + 1] {
        var transposition = bytes
        transposition.swapAt(middle, middle + 1)
        variants.append(String(decoding: transposition, as: UTF8.self))
    }

    var substitution = bytes
    substitution[middle] = substitution[middle] == Character("q").asciiValue
        ? Character("x").asciiValue!
        : Character("q").asciiValue!
    variants.append(String(decoding: substitution, as: UTF8.self))

    bytes.insert(Character("q").asciiValue!, at: middle)
    variants.append(String(decoding: bytes, as: UTF8.self))
    return Array(Set(variants)).sorted()
}
