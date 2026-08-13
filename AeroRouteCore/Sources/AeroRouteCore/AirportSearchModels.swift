import Foundation

public struct Airport: Sendable, Equatable, Identifiable {
    public let id: Int
    public let ident: String
    public let name: String
    public let countryCode: String
    public let countryName: String
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
        hasScheduledService: Bool,
        countryName: String = ""
    ) {
        self.id = id
        self.ident = ident
        self.name = name
        self.countryCode = countryCode
        self.countryName = countryName
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
    case codePrefix
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

public struct AirportSearchResult: Sendable, Equatable, Identifiable {
    public let airport: Airport
    public let score: Int
    public let reasons: [AirportMatchReason]
    public let confidence: AirportSearchConfidence
    public let isAmbiguous: Bool

    public var id: Int { airport.id }

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

/// Selects the search policy without exposing ranking implementation details.
public enum AirportSearchPhase: String, Sendable, Equatable, CaseIterable {
    /// The user is still changing the field. Code correction is disabled and
    /// the default result limit is eight.
    case editing

    /// The user committed the field. The complete fuzzy policy is enabled and
    /// the default result limit is twenty.
    case submitted
}

/// The single input contract shared by autocomplete and committed lookup.
public struct AirportSearchRequest: Sendable, Equatable {
    public let text: String
    public let phase: AirportSearchPhase
    public let limit: Int?

    public init(
        text: String,
        phase: AirportSearchPhase = .submitted,
        limit: Int? = nil
    ) {
        self.text = text
        self.phase = phase
        self.limit = limit
    }
}

/// A UI-facing state. Consumers should switch on this value instead of
/// interpreting raw relevance scores.
public enum AirportSearchResolution: String, Sendable, Equatable, CaseIterable {
    /// The input contains no supported searchable English text.
    case emptyInput

    /// The input is searchable but no airport met the relevance threshold.
    case noMatches

    /// Incremental results are available while the user is editing.
    case suggestions

    /// Submitted results exist, but the user must select one.
    case manualSelection

    /// The first result is exact and unambiguous, so it is safe to fill.
    case automaticSelection
}

/// The single output contract returned for every lookup phase.
public struct AirportSearchResponse: Sendable, Equatable {
    public let request: AirportSearchRequest
    public let normalizedText: String
    public let resolution: AirportSearchResolution
    public let results: [AirportSearchResult]

    public init(
        request: AirportSearchRequest,
        normalizedText: String,
        resolution: AirportSearchResolution,
        results: [AirportSearchResult]
    ) {
        self.request = request
        self.normalizedText = normalizedText
        self.resolution = resolution
        self.results = results
    }

    /// Non-nil only when `resolution == .automaticSelection`.
    public var automaticSelection: AirportSearchResult? {
        resolution == .automaticSelection ? results.first : nil
    }
}

struct NormalizedAirportQuery: Sendable, Equatable {
    private static let expansions = [
        "airpt": "airport",
        "apt": "airport",
        "intl": "international",
    ]
    private static let descriptorTerms: Set<String> = [
        "airport", "airports", "airfield", "international", "regional",
    ]

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
        tokens = rawTokens.map { Self.expansions[$0] ?? $0 }
        significantTokens = tokens.filter { !Self.descriptorTerms.contains($0) }
        compact = significantTokens.joined()

        codeCandidates = rawTokens.compactMap { token in
            guard rawTokens.count == 1,
                  token.count == 3 || token.count == 4,
                  token.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) })
            else { return nil }
            return token.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
        possibleCode = rawTokens.count == 1 ? codeCandidates.first : nil
        fuzzyCodeCandidate = significantTokens.count == 1 ? codeCandidates.first : nil
    }

    var isEmpty: Bool {
        significantTokens.isEmpty
    }
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
