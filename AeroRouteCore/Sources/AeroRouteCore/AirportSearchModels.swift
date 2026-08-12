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
    case exactAlias
    case aliasPrefix
    case acronym
    case allTerms
    case tokenMatch
    case fuzzyCode
    case fuzzyName
    case fuzzyCity
    case fuzzyAlias
    case fuzzyPhrase
}

public enum AirportSearchConfidence: String, Sendable, Equatable, Comparable {
    case low
    case medium
    case high
    case exact

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .exact: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
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
    public let confidence: AirportSearchConfidence
    public let isAmbiguous: Bool

    public init(
        airport: Airport,
        score: Int,
        reasons: [AirportMatchReason],
        confidence: AirportSearchConfidence = .medium,
        isAmbiguous: Bool = false
    ) {
        self.airport = airport
        self.score = score
        self.reasons = reasons
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
    }
}

struct NormalizedAirportQuery: Sendable, Equatable {
    private static let expansions = [
        "airpt": "airport",
        "apt": "airport",
        "intl": "international",
    ]
    private static let noiseWords: Set<String> = [
        "a", "an", "airport", "airports", "airfield", "at", "find", "flight",
        "flights", "fly", "for", "in", "international", "me", "near", "please",
        "regional", "search", "the", "to",
    ]
    private static let nonCodeWords: Set<String> = noiseWords.union([
        "city", "intl", "port",
    ])

    let original: String
    let normalized: String
    let tokens: [String]
    let significantTokens: [String]
    let codeCandidates: [String]
    let fuzzyCodeCandidate: String?
    let compact: String
    let possibleCode: String?

    init(_ input: String) {
        original = input
        normalized = airportSearchText(input)
        let rawTokens = normalized.split(separator: " ").map(String.init)
        let uppercaseTokens = Set(
            airportCasePreservingText(input).split(separator: " ").map(String.init).filter {
                $0.count == 3 || $0.count == 4
            }.filter {
                $0.unicodeScalars.allSatisfy {
                    $0.isASCII && CharacterSet.uppercaseLetters.contains($0)
                }
            }.map { $0.lowercased() }
        )
        tokens = rawTokens.map { Self.expansions[$0] ?? $0 }
        significantTokens = tokens.filter { !Self.noiseWords.contains($0) }
        compact = significantTokens.joined()

        codeCandidates = rawTokens.compactMap { token in
            guard !Self.nonCodeWords.contains(token),
                  rawTokens.count == 1 || uppercaseTokens.contains(token),
                  token.count == 3 || token.count == 4,
                  token.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) })
            else { return nil }
            return token.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
        possibleCode = rawTokens.count == 1 ? codeCandidates.first : nil
        fuzzyCodeCandidate = significantTokens.count == 1 ? codeCandidates.first : nil
    }

    var isEmpty: Bool { significantTokens.isEmpty && codeCandidates.isEmpty }
}

func airportSearchText(_ value: String) -> String {
    let locale = Locale(identifier: "en_US_POSIX")
    let folded = value.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
    )
    let scalars = folded.unicodeScalars.map { scalar -> Character in
        if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
            return Character(String(scalar))
        }
        return " "
    }
    return String(scalars)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

private func airportCasePreservingText(_ value: String) -> String {
    let folded = value.folding(
        options: [.diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
    )
    return String(folded.unicodeScalars.map { scalar -> Character in
        if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
            return Character(String(scalar))
        }
        return " "
    })
}
