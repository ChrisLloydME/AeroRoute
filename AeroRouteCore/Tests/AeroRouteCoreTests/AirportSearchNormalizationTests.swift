import Testing
@testable import AeroRouteCore

@Suite struct AirportSearchNormalizationTests {
    @Test func normalizesUnicodePunctuationWidthAndDiacritics() {
        #expect(airportSearchText("  São—Paulo ✈️ ") == "sao paulo")
        #expect(airportSearchText("ＭＵＣ") == "muc")
        #expect(airportSearchText("Shànghǎi (Pudong)") == "shanghai pudong")
    }

    @Test func deliberatelyIgnoresNonEnglishScripts() {
        #expect(airportSearchText("上海") == "")
        #expect(airportSearchText("Москва") == "")
        #expect(NormalizedAirportQuery("上海✈️").isEmpty)
    }

    @Test func recognizesSingleNormalizedAirportCodes() {
        #expect(NormalizedAirportQuery(" pvg ").possibleCode == "PVG")
        #expect(NormalizedAirportQuery("ZSPD").possibleCode == "ZSPD")
        #expect(NormalizedAirportQuery("✈️ＰＶＧ🛬").possibleCode == "PVG")
        #expect(NormalizedAirportQuery("PVG airport").possibleCode == nil)
        #expect(NormalizedAirportQuery("PVG airport").codeCandidates.isEmpty)
        #expect(NormalizedAirportQuery("New York John Kennedy").codeCandidates.isEmpty)
        #expect(NormalizedAirportQuery("new york PVG").codeCandidates.isEmpty)
        #expect(NormalizedAirportQuery("✈️").isEmpty)
        #expect(NormalizedAirportQuery("🇨🇳").isEmpty)
    }

    @Test func expandsCommonAirportAbbreviationsWithoutParsingSentences() {
        let query = NormalizedAirportQuery("Heathrow Intl")

        #expect(query.tokens == ["heathrow", "international"])
        #expect(query.significantTokens == ["heathrow"])
        #expect(query.compact == "heathrow")
        #expect(NormalizedAirportQuery("airport").isEmpty)
    }
}
