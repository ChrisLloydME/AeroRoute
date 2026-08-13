import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct AirportSearchEngineTests {
    private static let engine = try! AirportSearchEngine()

    @Test func exactCodesHaveHighestConfidence() throws {
        let engine = Self.engine

        let iata = engine.search(" pvg ")
        #expect(iata.first?.airport.icaoCode == "ZSPD")
        #expect(iata.first?.reasons.contains(.exactIATA) == true)
        #expect(iata.first?.confidence == .exact)
        #expect(iata.first?.isAmbiguous == false)

        let icao = engine.search("EGLL")
        #expect(icao.first?.airport.iataCode == "LHR")
        #expect(icao.first?.reasons.contains(.exactICAO) == true)
    }

    @Test func cityAndNameQueriesReturnRelevantAirports() throws {
        let engine = Self.engine

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
        let engine = Self.engine

        #expect(engine.count > 9_000)
        #expect(engine.search("✈️🇨🇳🛫").isEmpty)
        #expect(engine.search("London", limit: 0).isEmpty)
        #expect(engine.search("airport", limit: 3).isEmpty)
    }

    @Test func toleratesEnglishTyposAndDecorativeUnicode() throws {
        let engine = Self.engine

        let shanghaiTypo = engine.search("Shanghi")
        #expect(shanghaiTypo.first?.airport.municipality?.hasPrefix("Shanghai") == true)
        #expect(shanghaiTypo.prefix(2).map(\.airport.iataCode).contains("PVG"))
        #expect(shanghaiTypo.prefix(2).map(\.airport.iataCode).contains("SHA"))
        #expect(engine.search("Pudng").first?.airport.iataCode == "PVG")
        #expect(engine.search("上海").isEmpty)
        #expect(engine.search("✈️ＰＶＧ🛬").first?.airport.iataCode == "PVG")
        #expect(engine.search("✈️ＰＶＧ🛬").first?.reasons.contains(.exactIATA) == true)
    }

    @Test func combinesFieldsAndReturnsStableOrdering() throws {
        let engine = Self.engine

        let mixed = engine.search("CN PVG Pudong")
        #expect(mixed.first?.airport.iataCode == "PVG")
        #expect(mixed.first?.reasons.contains(.allTerms) == true)

        let firstRun = engine.search("London airport", limit: 12).map(\.airport.id)
        let secondRun = engine.search("London airport", limit: 12).map(\.airport.id)
        #expect(firstRun == secondRun)
        #expect(Set(firstRun).count == firstRun.count)
    }

    @Test func fuzzyFourLetterCodeCanRecoverOneMistypedCharacter() throws {
        let engine = Self.engine

        let results = engine.search("ZSPC", limit: 20)
        let pudong = results.first { $0.airport.icaoCode == "ZSPD" }
        #expect(pudong != nil)
        #expect(pudong?.reasons.contains(.fuzzyCode) == true)
        #expect(pudong?.confidence == .low)
    }

    @Test func understandsEnglishAliasesAbbreviationsAndAcronyms() {
        #expect(Self.engine.search("Idlewild").first?.airport.iataCode == "JFK")
        #expect(Self.engine.search("Heathrow Intl").first?.airport.iataCode == "LHR")
        let initials = Self.engine.search("LH")
        #expect(initials.contains { $0.airport.iataCode == "LHR" })
        #expect(initials.first?.reasons.contains(.acronym) == true)
        #expect(initials.first?.isAmbiguous == true)

        let nyc = Self.engine.search("NYC", limit: 10)
        #expect(nyc.contains { $0.airport.iataCode == "JFK" })
        #expect(nyc.first?.reasons.contains(.exactAlias) == true)

        let lon = Self.engine.search("LON", limit: 10)
        #expect(lon.contains { $0.airport.iataCode == "LHR" })
        #expect(lon.contains { $0.airport.iataCode == "LGW" })
        #expect(lon.first?.isAmbiguous == true)
    }

    @Test func matchesTermsAcrossEnglishFieldsInAnyOrder() {
        #expect(Self.engine.search("Paris Charles Gaulle").first?.airport.iataCode == "CDG")
        #expect(Self.engine.search("New York John Kennedy").first?.airport.iataCode == "JFK")
        #expect(Self.engine.search("United Kingdom Heathrow").first?.airport.iataCode == "LHR")
    }

    @Test func handlesTranspositionsMergedWordsAndPhraseTypos() {
        #expect(airportEditDistance("heathorw", "heathrow", limit: 1) == 1)
        #expect(Self.engine.search("Heathorw").first?.airport.iataCode == "LHR")
        #expect(Self.engine.search("newyorkcity").contains { $0.airport.iataCode == "JFK" })
        #expect(Self.engine.search("sanfransisco").first?.airport.iataCode == "SFO")
    }

    @Test func marksCityQueriesAsAmbiguousButCodesAsDecisive() {
        let london = Self.engine.search("London", limit: 10)
        #expect(london.first?.isAmbiguous == true)
        #expect(london.first?.confidence == .medium)
        #expect(london.filter(\.isAmbiguous).count > 1)

        let heathrow = Self.engine.search("LHR")
        #expect(heathrow.first?.isAmbiguous == false)
        #expect(heathrow.first?.confidence == .exact)
    }

    @Test func rejectsUnsupportedOrInsufficientInputInsteadOfGuessing() {
        #expect(Self.engine.search("上海").isEmpty)
        #expect(Self.engine.search("airport").isEmpty)
        #expect(Self.engine.search("qzxqzxqz").isEmpty)
    }

    @Test func suggestionsNarrowAsTheUserTypesAnAirportCode() {
        let p = Self.engine.suggestions(for: "p")
        let pv = Self.engine.suggestions(for: "pv")
        let pvg = Self.engine.suggestions(for: "pvg")

        #expect(!p.isEmpty)
        #expect(pv.contains { $0.airport.iataCode == "PVG" })
        #expect(pvg.first?.airport.iataCode == "PVG")
        #expect(pvg.first?.confidence == .exact)
        #expect(pvg.first?.reasons.contains(.exactIATA) == true)
    }

    @Test func suggestionsSupportNameAndCityPrefixesFromOneCharacter() {
        let s = Self.engine.suggestions(for: "s", limit: 10)
        let sh = Self.engine.suggestions(for: "sh", limit: 10)
        let shang = Self.engine.suggestions(for: "shang", limit: 10)

        #expect(!s.isEmpty)
        #expect(sh.contains { $0.reasons.contains(.codePrefix) })
        #expect(shang.prefix(3).contains { $0.airport.iataCode == "PVG" })
        #expect(shang.prefix(3).contains { $0.airport.iataCode == "SHA" })
    }

    @Test func suggestionsAvoidCodeCorrectionWhileTheUserIsStillTyping() {
        let partial = Self.engine.suggestions(for: "ZSPC", limit: 20)
        #expect(partial.allSatisfy { !$0.reasons.contains(.fuzzyCode) })

        let submitted = Self.engine.search("ZSPC", limit: 20)
        #expect(submitted.contains {
            $0.airport.icaoCode == "ZSPD" && $0.reasons.contains(.fuzzyCode)
        })
    }
}
