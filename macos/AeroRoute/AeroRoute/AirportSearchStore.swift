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

@MainActor
final class AirportSearchStore: ObservableObject {
    enum Availability: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var availability: Availability
    @Published private var catalogAirports: [AirportSearchCandidate] = []
    private let provider: (any AirportSearchProviding)?

    init() {
        provider = nil
        availability = .loading
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AirportCatalog.airportsAlphabetically() }
            }.value
            guard let self else { return }
            switch result {
            case let .success(entries):
                catalogAirports = entries.map {
                    AirportSearchCandidate(
                        id: $0.id,
                        code: $0.iataCode,
                        name: $0.name,
                        municipality: $0.municipality,
                        countryCode: $0.countryCode,
                        countryName: $0.countryName,
                        icaoCode: $0.icaoCode,
                        isExactCodeMatch: false
                    )
                }
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
        if let response = lookup(text: code, phase: .submitted, limit: 1),
           let airport = response.automaticSelection,
           airport.isExactCodeMatch {
            return airport
        }
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        guard normalizedCode.count == 3 else { return nil }
        return catalogAirports.first { $0.code == normalizedCode }
    }

    func airportsAlphabetically() -> [AirportSearchCandidate] {
        (provider?.airportsAlphabetically() ?? catalogAirports).sorted { lhs, rhs in
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
