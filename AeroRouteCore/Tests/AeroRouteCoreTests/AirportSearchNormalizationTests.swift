import Testing
@testable import AeroRouteCore

@Suite struct AirportSearchNormalizationTests {
    @Test func normalizesUnicodePunctuationWidthAndDiacritics() {
        #expect(airportSearchText("  São—Paulo ✈️ ") == "sao paulo")
        #expect(airportSearchText("ＭＵＣ") == "muc")
        #expect(airportSearchText("Shànghǎi (Pudong)") == "shanghai pudong")
    }

    @Test func transliteratesNonLatinInputWhenFoundationCan() {
        #expect(airportSearchText("上海") == "shang hai")
        #expect(airportSearchText("Москва") == "moskva")
    }

    @Test func recognizesSingleNormalizedAirportCodes() {
        #expect(NormalizedAirportQuery(" pvg ").possibleCode == "PVG")
        #expect(NormalizedAirportQuery("ZSPD").possibleCode == "ZSPD")
        #expect(NormalizedAirportQuery("✈️ＰＶＧ🛬").possibleCode == "PVG")
        #expect(NormalizedAirportQuery("PVG airport").possibleCode == nil)
        #expect(NormalizedAirportQuery("✈️").isEmpty)
        #expect(NormalizedAirportQuery("🇨🇳").isEmpty)
    }
}
