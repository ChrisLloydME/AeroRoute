import AeroRouteCore
import Combine
import Foundation

struct AirportSearchCandidate: Equatable, Identifiable, Sendable {
    let id: Int
    let code: String
    let name: String
    let municipality: String?
    let countryCode: String
    let countryName: String
    let icaoCode: String?
    let isExactCodeMatch: Bool
}

enum AirportSearchQueryPhase: Equatable, Sendable {
    case editing
    case submitted
}

enum AirportSearchPresentation: Equatable, Sendable {
    case emptyInput
    case noMatches
    case suggestions
    case manualSelection
    case automaticSelection
}

struct AirportSearchSnapshot: Equatable, Sendable {
    let text: String
    let presentation: AirportSearchPresentation
    let candidates: [AirportSearchCandidate]

    var automaticSelection: AirportSearchCandidate? {
        presentation == .automaticSelection ? candidates.first : nil
    }
}

/// UI-owned boundary for the independently developed airport search engine.
/// The core integration only needs to translate its stable response into this model.
protocol AirportSearchProviding: Sendable {
    /// Returns all selectable airports ordered by localized-independent airport name.
    /// This powers the picker before the user enters a query.
    func airportsAlphabetically() -> [AirportSearchCandidate]

    func lookup(
        text: String,
        phase: AirportSearchQueryPhase,
        limit: Int?
    ) -> AirportSearchSnapshot
}

struct AirportSearchEngineAdapter: AirportSearchProviding {
    private let engine: AirportSearchEngine
    private let catalogAirports: [AirportSearchCandidate]

    init(
        engine: AirportSearchEngine,
        catalogEntries: [AirportCatalogEntry]
    ) {
        self.engine = engine
        catalogAirports = catalogEntries.map(Self.candidate)
    }

    init() throws {
        try self.init(
            engine: AirportSearchEngine(),
            catalogEntries: AirportCatalog.airportsAlphabetically()
        )
    }

    func airportsAlphabetically() -> [AirportSearchCandidate] {
        catalogAirports
    }

    func lookup(
        text: String,
        phase: AirportSearchQueryPhase,
        limit: Int?
    ) -> AirportSearchSnapshot {
        let response = engine.lookup(AirportSearchRequest(
            text: text,
            phase: phase.corePhase,
            limit: limit
        ))
        let candidates = response.results.compactMap { result in
            Self.candidate(result.airport, matchReasons: result.reasons)
        }
        return AirportSearchSnapshot(
            text: response.normalizedText,
            presentation: response.resolution.presentation(
                hasSelectableCandidates: !candidates.isEmpty
            ),
            candidates: candidates
        )
    }

    nonisolated private static func candidate(
        _ entry: AirportCatalogEntry
    ) -> AirportSearchCandidate {
        AirportSearchCandidate(
            id: entry.id,
            code: entry.iataCode,
            name: entry.name,
            municipality: entry.municipality,
            countryCode: entry.countryCode,
            countryName: entry.countryName,
            icaoCode: entry.icaoCode,
            isExactCodeMatch: false
        )
    }

    nonisolated private static func candidate(
        _ airport: Airport,
        matchReasons: [AirportMatchReason]
    ) -> AirportSearchCandidate? {
        guard let iataCode = airport.iataCode,
              iataCode.count == 3 else { return nil }
        return AirportSearchCandidate(
            id: airport.id,
            code: iataCode,
            name: airport.name,
            municipality: airport.municipality,
            countryCode: airport.countryCode,
            countryName: airport.countryName,
            icaoCode: airport.icaoCode,
            isExactCodeMatch: matchReasons.contains(.exactIATA)
        )
    }
}

private extension AirportSearchQueryPhase {
    var corePhase: AirportSearchPhase {
        switch self {
        case .editing: .editing
        case .submitted: .submitted
        }
    }
}

private extension AirportSearchResolution {
    func presentation(hasSelectableCandidates: Bool) -> AirportSearchPresentation {
        guard hasSelectableCandidates || self == .emptyInput else { return .noMatches }
        switch self {
        case .emptyInput: return .emptyInput
        case .noMatches: return .noMatches
        case .suggestions: return .suggestions
        case .manualSelection: return .manualSelection
        case .automaticSelection: return .automaticSelection
        }
    }
}

@MainActor
final class AirportSearchStore: ObservableObject {
    enum Availability: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var availability: Availability
    private var provider: (any AirportSearchProviding)?

    init() {
        provider = nil
        availability = .loading
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    (
                        try AirportSearchEngine(),
                        try AirportCatalog.airportsAlphabetically()
                    )
                }
            }.value
            guard let self else { return }
            switch result {
            case let .success((engine, catalogEntries)):
                provider = AirportSearchEngineAdapter(
                    engine: engine,
                    catalogEntries: catalogEntries
                )
                availability = .ready
            case let .failure(error):
                availability = .unavailable(error.localizedDescription)
            }
        }
    }

    init(provider: any AirportSearchProviding) {
        self.provider = provider
        availability = .ready
    }

    func lookup(
        text: String,
        phase: AirportSearchQueryPhase,
        limit: Int? = nil
    ) -> AirportSearchSnapshot? {
        provider?.lookup(text: text, phase: phase, limit: limit)
    }

    func exactCodeMatch(_ code: String) -> AirportSearchCandidate? {
        guard let response = lookup(text: code, phase: .submitted, limit: 1),
              let airport = response.automaticSelection,
              airport.isExactCodeMatch else { return nil }
        return airport
    }

    func airportsAlphabetically() -> [AirportSearchCandidate] {
        (provider?.airportsAlphabetically() ?? []).sorted { lhs, rhs in
            let order = lhs.name.compare(
                rhs.name,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: nil,
                locale: Locale(identifier: "en_US_POSIX")
            )
            if order != .orderedSame { return order == .orderedAscending }
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            return lhs.id < rhs.id
        }
    }
}
