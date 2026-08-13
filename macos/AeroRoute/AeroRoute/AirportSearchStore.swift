import Combine
import Foundation

struct AirportSearchCandidate: Equatable, Identifiable, Sendable {
    let id: Int
    let code: String
    let name: String
    let municipality: String?
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
    func lookup(
        text: String,
        phase: AirportSearchQueryPhase,
        limit: Int?
    ) -> AirportSearchSnapshot
}

@MainActor
final class AirportSearchStore: ObservableObject {
    enum Availability: Equatable {
        case ready
        case unavailable(String)
    }

    @Published private(set) var availability: Availability
    private let provider: (any AirportSearchProviding)?

    init() {
        provider = nil
        availability = .unavailable("Airport search is not included in this build.")
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
        let response = lookup(text: code, phase: .submitted, limit: 1)
        guard let airport = response?.automaticSelection,
              airport.isExactCodeMatch else { return nil }
        return airport
    }
}
