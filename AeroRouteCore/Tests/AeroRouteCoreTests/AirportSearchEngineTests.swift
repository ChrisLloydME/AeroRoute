import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportSearchEngineTests {
    @Test func exactCodesHaveHighestConfidence() throws {
        let engine = try AirportSearchEngine()

        let iata = engine.search(" pvg ")
        #expect(iata.first?.airport.icaoCode == "ZSPD")
        #expect(iata.first?.reasons.contains(.exactIATA) == true)

        let icao = engine.search("EGLL")
        #expect(icao.first?.airport.iataCode == "LHR")
        #expect(icao.first?.reasons.contains(.exactICAO) == true)
    }

    @Test func cityAndNameQueriesReturnRelevantAirports() throws {
        let engine = try AirportSearchEngine()

        let london = engine.search("London", limit: 10)
        #expect(london.contains { $0.airport.iataCode == "LHR" })
        #expect(london.contains { $0.airport.iataCode == "LGW" })

        let countryAndCity = engine.search("Shanghai CN")
        #expect(countryAndCity.prefix(2).map(\.airport.iataCode).contains("PVG"))
        #expect(countryAndCity.prefix(2).map(\.airport.iataCode).contains("SHA"))

        let name = engine.search("Pudong International")
        #expect(name.first?.airport.iataCode == "PVG")
    }

    @Test func arbitraryTextIsSafeAndLimited() throws {
        let engine = try AirportSearchEngine()

        #expect(engine.count > 9_000)
        #expect(engine.search("✈️🇨🇳🛫").isEmpty)
        #expect(engine.search("London", limit: 0).isEmpty)
        #expect(engine.search("airport", limit: 3).count == 3)
    }

    @Test func toleratesTyposTransliterationAndDecorativeUnicode() throws {
        let engine = try AirportSearchEngine()

        let shanghaiTypo = engine.search("Shanghi")
        #expect(shanghaiTypo.first?.airport.municipality?.hasPrefix("Shanghai") == true)
        #expect(shanghaiTypo.prefix(2).map(\.airport.iataCode).contains("PVG"))
        #expect(shanghaiTypo.prefix(2).map(\.airport.iataCode).contains("SHA"))
        #expect(engine.search("Pudng").first?.airport.iataCode == "PVG")
        #expect(engine.search("上海").prefix(2).map(\.airport.iataCode).contains("PVG"))
        #expect(engine.search("✈️ＰＶＧ🛬").first?.airport.iataCode == "PVG")
        #expect(engine.search("✈️ＰＶＧ🛬").first?.reasons.contains(.exactIATA) == true)
    }

    @Test func combinesFieldsAndReturnsStableOrdering() throws {
        let engine = try AirportSearchEngine()

        let mixed = engine.search("CN PVG Pudong")
        #expect(mixed.first?.airport.iataCode == "PVG")
        #expect(mixed.first?.reasons.contains(.allTerms) == true)

        let firstRun = engine.search("London airport", limit: 12).map(\.airport.id)
        let secondRun = engine.search("London airport", limit: 12).map(\.airport.id)
        #expect(firstRun == secondRun)
        #expect(Set(firstRun).count == firstRun.count)
    }

    @Test func fuzzyFourLetterCodeCanRecoverOneMistypedCharacter() throws {
        let engine = try AirportSearchEngine()

        let results = engine.search("ZSPC", limit: 20)
        let pudong = results.first { $0.airport.icaoCode == "ZSPD" }
        #expect(pudong != nil)
        #expect(pudong?.reasons.contains(.fuzzyCode) == true)
    }
}
