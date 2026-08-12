import Foundation

public struct Airport: Sendable, Equatable, Identifiable {
    public let id: Int
    public let ident: String
    public let name: String
    public let countryCode: String
    public let municipality: String?
    public let iataCode: String?
    public let icaoCode: String?
    public let latitude: Double
    public let longitude: Double
    public let type: String
    public let hasScheduledService: Bool

    public init(
        id: Int,
        ident: String,
        name: String,
        countryCode: String,
        municipality: String?,
        iataCode: String?,
        icaoCode: String?,
        latitude: Double,
        longitude: Double,
        type: String,
        hasScheduledService: Bool
    ) {
        self.id = id
        self.ident = ident
        self.name = name
        self.countryCode = countryCode
        self.municipality = municipality
        self.iataCode = iataCode
        self.icaoCode = icaoCode
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
        self.hasScheduledService = hasScheduledService
    }
}

public enum AirportMatchReason: String, Sendable, Equatable, CaseIterable {
    case exactIATA
    case exactICAO
    case exactName
    case exactCity
    case namePrefix
    case cityPrefix
    case allTerms
    case fuzzyCode
    case fuzzyName
    case fuzzyCity
}

public struct AirportSearchError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct AirportSearchResult: Sendable, Equatable {
    public let airport: Airport
    public let score: Int
    public let reasons: [AirportMatchReason]

    public init(airport: Airport, score: Int, reasons: [AirportMatchReason]) {
        self.airport = airport
        self.score = score
        self.reasons = reasons
    }
}

struct NormalizedAirportQuery: Sendable, Equatable {
    let original: String
    let normalized: String
    let tokens: [String]
    let possibleCode: String?

    init(_ input: String) {
        original = input
        normalized = airportSearchText(input)
        tokens = normalized.split(separator: " ").map(String.init)

        let code = normalized
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        if (code.count == 3 || code.count == 4),
           code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) && $0.isASCII }) {
            possibleCode = code
        } else {
            possibleCode = nil
        }
    }

    var isEmpty: Bool { tokens.isEmpty && possibleCode == nil }
}

func airportSearchText(_ value: String) -> String {
    let locale = Locale(identifier: "en_US_POSIX")
    let transliterated = value.applyingTransform(.toLatin, reverse: false) ?? value
    let folded = transliterated.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
    )
    let scalars = folded.unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) {
            return Character(String(scalar))
        }
        return " "
    }
    return String(scalars)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}
