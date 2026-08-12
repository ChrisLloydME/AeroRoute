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
        #expect(NormalizedAirportQuery("PVG airport").codeCandidates == ["PVG"])
        #expect(NormalizedAirportQuery("✈️").isEmpty)
        #expect(NormalizedAirportQuery("🇨🇳").isEmpty)
    }

    @Test func expandsEnglishAbbreviationsAndDropsQueryNoise() {
        let query = NormalizedAirportQuery("Please find Heathrow Intl Airport")

        #expect(query.tokens == ["please", "find", "heathrow", "international", "airport"])
        #expect(query.significantTokens == ["heathrow", "international"])
        #expect(query.compact == "heathrowinternational")
        #expect(NormalizedAirportQuery("airport please").isEmpty)
    }
}
