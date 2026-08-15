import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportSearchQualityTests {
    private static let engine = try! AirportSearchEngine()

    private struct TopMatchCase {
        let query: String
        let iata: String
    }

    @Test func ranksRepresentativeExactAndDescriptiveQueriesFirst() {
        let cases = [
            TopMatchCase(query: "Amsterdam Schiphol", iata: "AMS"),
            TopMatchCase(query: "Singapore Changi", iata: "SIN"),
            TopMatchCase(query: "Tokyo Haneda", iata: "HND"),
            TopMatchCase(query: "Tokyo Narita", iata: "NRT"),
            TopMatchCase(query: "Paris Charles de Gaulle", iata: "CDG"),
            TopMatchCase(query: "San Francisco", iata: "SFO"),
            TopMatchCase(query: "Los Angeles", iata: "LAX"),
            TopMatchCase(query: "Dubai", iata: "DXB"),
            TopMatchCase(query: "Frankfurt Main", iata: "FRA"),
            TopMatchCase(query: "Munich Franz Josef Strauss", iata: "MUC"),
            TopMatchCase(query: "Sydney Kingsford Smith", iata: "SYD"),
            TopMatchCase(query: "New York John Kennedy", iata: "JFK"),
        ]

        for item in cases {
            #expect(
                Self.engine.search(item.query).first?.airport.iataCode == item.iata,
                "Expected \(item.query) to rank \(item.iata) first"
            )
        }
    }

    @Test func ranksRepresentativeMisspellingsFirst() {
        let cases = [
            TopMatchCase(query: "Schipol", iata: "AMS"),
            TopMatchCase(query: "Chnagi", iata: "SIN"),
            TopMatchCase(query: "Haneda", iata: "HND"),
            TopMatchCase(query: "Naritta", iata: "NRT"),
            TopMatchCase(query: "Charles de Gualle", iata: "CDG"),
            TopMatchCase(query: "San Fransisco", iata: "SFO"),
            TopMatchCase(query: "Los Angles", iata: "LAX"),
            TopMatchCase(query: "Dubia", iata: "DXB"),
            TopMatchCase(query: "Frankfort Main", iata: "FRA"),
            TopMatchCase(query: "Amsterdm Schipol", iata: "AMS"),
        ]

        for item in cases {
            #expect(
                Self.engine.search(item.query).first?.airport.iataCode == item.iata,
                "Expected typo query \(item.query) to rank \(item.iata) first"
            )
        }
    }

    @Test func incrementalPrefixKeepsTheIntendedAirportInTheVisibleResults() {
        // Very short prefixes are intentionally allowed to favor possible airport codes.
        // Once the input is distinctive enough, the intended name must remain visible.
        for prefix in ["schi", "schip", "schiph"] {
            #expect(
                Self.engine.suggestions(for: prefix, limit: 8).contains {
                    $0.airport.iataCode == "AMS"
                },
                "Expected \(prefix) to keep AMS visible"
            )
        }
    }

    @Test func weakAndNonsenseQueriesDoNotCreateConfidentFalsePositives() {
        for query in ["qzxqzxqz", "zzzzzzzz", "airport", "international airport"] {
            #expect(Self.engine.search(query).isEmpty)
        }
    }
}
