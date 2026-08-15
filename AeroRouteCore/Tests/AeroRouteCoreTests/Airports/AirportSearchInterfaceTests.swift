import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportSearchInterfaceTests {
    private static let engine = try! AirportSearchEngine()

    @Test func editingAndSubmittedLookupShareOneContract() {
        let editingRequest = AirportSearchRequest(text: "pvg", phase: .editing)
        let editing = Self.engine.lookup(editingRequest)

        #expect(editing.request == editingRequest)
        #expect(editing.normalizedText == "pvg")
        #expect(editing.resolution == .suggestions)
        #expect(editing.results.count <= 8)
        #expect(editing.results.first?.airport.iataCode == "PVG")
        #expect(editing.automaticSelection == nil)

        let submitted = Self.engine.lookup(.init(text: "✈️ＰＶＧ🛬"))
        #expect(submitted.normalizedText == "pvg")
        #expect(submitted.resolution == .automaticSelection)
        #expect(submitted.automaticSelection?.airport.iataCode == "PVG")
        #expect(submitted.automaticSelection?.airport.countryCode == "CN")
        #expect(submitted.automaticSelection?.airport.countryName == "China")
    }

    @Test func responseDistinguishesEmptyNoMatchAndManualSelection() {
        let empty = Self.engine.lookup(.init(text: "✈️🇨🇳"))
        #expect(empty.resolution == .emptyInput)
        #expect(empty.results.isEmpty)

        let noMatch = Self.engine.lookup(.init(text: "qzxqzxqz"))
        #expect(noMatch.resolution == .noMatches)
        #expect(noMatch.results.isEmpty)

        let ambiguous = Self.engine.lookup(.init(text: "London", limit: 10))
        #expect(ambiguous.resolution == .manualSelection)
        #expect(ambiguous.automaticSelection == nil)
        #expect(ambiguous.results.contains { $0.airport.iataCode == "LHR" })
        #expect(ambiguous.results.contains { $0.airport.iataCode == "LGW" })
    }

    @Test func explicitLimitAndStableResultIdentityArePreserved() {
        let response = Self.engine.lookup(.init(text: "Paris", phase: .editing, limit: 2))
        #expect(response.results.count <= 2)
        #expect(response.results.allSatisfy { $0.id == $0.airport.id })
    }

    @Test func compatibilityMethodsMatchTheUnifiedInterface() {
        let submitted = Self.engine.lookup(.init(text: "Heathrow", limit: 5)).results
        #expect(Self.engine.search("Heathrow", limit: 5) == submitted)

        let editing = Self.engine.lookup(
            .init(text: "heat", phase: .editing, limit: 5)
        ).results
        #expect(Self.engine.suggestions(for: "heat", limit: 5) == editing)
    }

    @Test func oversizedInputFailsClosedWithoutExpensiveFuzzyWork() {
        let text = String(repeating: "heathrow", count: 200)
        let request = AirportSearchRequest(text: text)

        let response = Self.engine.lookup(request)

        #expect(response.request == request)
        #expect(response.normalizedText.isEmpty)
        #expect(response.resolution == .noMatches)
        #expect(response.results.isEmpty)
    }

    @Test func repeatedTermsDoNotAccumulateArtificialRelevance() {
        let repeated = Self.engine.lookup(.init(text: "heathrow heathrow heathrow"))
        let single = Self.engine.lookup(.init(text: "heathrow"))

        #expect(repeated.results.first?.airport.id == single.results.first?.airport.id)
        #expect(repeated.results.first?.score == single.results.first?.score)
        #expect(repeated.results.first?.reasons == single.results.first?.reasons)
    }
}
