import CSQLite
import Foundation

public final class AirportSearchEngine: @unchecked Sendable {
    private struct SearchableAirport: Sendable {
        let airport: Airport
        let name: String
        let city: String
        let country: String
        let aliases: [String]
        let nameWords: Set<String>
        let cityWords: Set<String>
        let countryWords: Set<String>
        let aliasWords: Set<String>
        let nameCompact: String
        let cityCompact: String
        let countryCompact: String
        let aliasCompacts: [String]
        let compactFields: Set<String>
        let acronyms: Set<String>
    }

    private struct RankedAirport {
        let result: AirportSearchResult
        let typeRank: Int
    }

    private struct TokenEvidence {
        let points: Int
        let reason: AirportMatchReason
    }

    private struct RankedLocation {
        let candidate: AirportProximityCandidate
        let adjustedDistanceKM: Double
    }

    private struct SearchPolicy {
        let minimumPrefixLength: Int
        let codePrefixPoints: Int
        let allowsFuzzyText: Bool
        let allowsFuzzyCode: Bool
        let candidateBudget: Int?

        static let submitted = SearchPolicy(
            minimumPrefixLength: 2,
            codePrefixPoints: 0,
            allowsFuzzyText: true,
            allowsFuzzyCode: true,
            candidateBudget: nil
        )

        static func suggestions(for query: NormalizedAirportQuery) -> SearchPolicy {
            SearchPolicy(
                minimumPrefixLength: 1,
                codePrefixPoints: 720,
                allowsFuzzyText: query.compact.count >= 4,
                allowsFuzzyCode: false,
                candidateBudget: query.compact.count <= 2 ? 512 : nil
            )
        }
    }

    private struct SearchIndexes: Sendable {
        struct IndexedTerm: Sendable {
            let value: String
            let bytes: [UInt8]
            let characterMask: UInt32
        }

        var words: [String: [Int]] = [:]
        var codes: [String: [Int]] = [:]
        var acronyms: [String: [Int]] = [:]
        var compactFields: [String: [Int]] = [:]
        var orderedWords: [String] = []
        var wordsByLength: [Int: [IndexedTerm]] = [:]
        var compactFieldsByLength: [Int: [IndexedTerm]] = [:]
        var knownCodes: Set<String> = []
    }

    private static let acronymNoise: Set<String> = [
        "airport", "airfield", "and", "at", "de", "international", "of", "regional",
        "the",
    ]
    private static let aliasNoise: Set<String> = [
        "airport", "airfield", "international", "municipal", "regional",
    ]

    private let airports: [SearchableAirport]
    private let indexes: SearchIndexes

    public convenience init() throws {
        try self.init(databaseURL: AirportDatabaseResource.url)
    }

    public init(databaseURL: URL) throws {
        airports = try Self.loadAirports(from: databaseURL)
        indexes = Self.makeIndexes(for: airports)
    }

    public var count: Int { airports.count }

    /// Unified UI-facing entry point for both incremental and submitted lookup.
    public func lookup(_ request: AirportSearchRequest) -> AirportSearchResponse {
        let query = NormalizedAirportQuery(request.text)
        let defaultLimit = request.phase == .editing ? 8 : 20
        let limit = max(0, request.limit ?? defaultLimit)
        let results: [AirportSearchResult]
        switch request.phase {
        case .editing:
            results = rankedResults(
                query,
                limit: limit,
                policy: .suggestions(for: query)
            )
        case .submitted:
            results = rankedResults(query, limit: limit, policy: .submitted)
        }

        let resolution: AirportSearchResolution
        if query.isEmpty {
            resolution = .emptyInput
        } else if results.isEmpty {
            resolution = .noMatches
        } else if request.phase == .editing {
            resolution = .suggestions
        } else if results[0].confidence == .exact, !results[0].isAmbiguous {
            resolution = .automaticSelection
        } else {
            resolution = .manualSelection
        }

        return AirportSearchResponse(
            request: request,
            normalizedText: query.normalized,
            resolution: resolution,
            results: results
        )
    }

    /// Compatibility wrapper. New UI code should call `lookup(_:)`.
    public func search(_ input: String, limit: Int = 20) -> [AirportSearchResult] {
        lookup(AirportSearchRequest(text: input, phase: .submitted, limit: limit)).results
    }

    /// Returns low-latency incremental candidates suitable for search-as-you-type UI.
    /// Fuzzy text matching starts at four characters and code correction is disabled.
    /// Compatibility wrapper. New UI code should call `lookup(_:)`.
    public func suggestions(for input: String, limit: Int = 8) -> [AirportSearchResult] {
        lookup(AirportSearchRequest(text: input, phase: .editing, limit: limit)).results
    }

    /// Finds airports near one coordinate. Distance is always the primary signal;
    /// scheduled service, IATA availability and airport size only break close ties.
    public func airports(near request: AirportProximityRequest) -> AirportProximityResponse {
        proximityResponse(request: request, evidence: [request.coordinate])
    }

    /// Infers both airports from the first and last portions of an ordered track.
    public func matchAirports(
        for track: Track,
        options: AirportTrackMatchOptions = .init()
    ) -> AirportTrackMatchResponse {
        guard let firstPoint = track.points.first, let lastPoint = track.points.last else {
            let invalidRequest = AirportProximityRequest(
                coordinate: AirportCoordinate(latitude: .nan, longitude: .nan),
                limit: options.limit,
                maximumDistanceKM: options.maximumDistanceKM,
                prefersScheduledService: options.prefersScheduledService
            )
            let invalid = airports(near: invalidRequest)
            return AirportTrackMatchResponse(origin: invalid, destination: invalid)
        }
        let originCoordinate = AirportCoordinate(
            latitude: firstPoint.latitude,
            longitude: firstPoint.longitude
        )
        let destinationCoordinate = AirportCoordinate(
            latitude: lastPoint.latitude,
            longitude: lastPoint.longitude
        )
        let originRequest = AirportProximityRequest(
            coordinate: originCoordinate,
            limit: options.limit,
            maximumDistanceKM: options.maximumDistanceKM,
            prefersScheduledService: options.prefersScheduledService
        )
        let destinationRequest = AirportProximityRequest(
            coordinate: destinationCoordinate,
            limit: options.limit,
            maximumDistanceKM: options.maximumDistanceKM,
            prefersScheduledService: options.prefersScheduledService
        )
        return AirportTrackMatchResponse(
            origin: proximityResponse(
                request: originRequest,
                evidence: endpointEvidence(track, origin: true, options: options),
                supportingRadiusKM: options.supportingRadiusKM
            ),
            destination: proximityResponse(
                request: destinationRequest,
                evidence: endpointEvidence(track, origin: false, options: options),
                supportingRadiusKM: options.supportingRadiusKM
            )
        )
    }

    /// Matches each imported CSV independently and preserves input order. No
    /// continuity, endpoint evidence, or ranking signal crosses file boundaries.
    public func matchAirportFiles(
        _ legs: [ImportedLeg],
        options: AirportTrackMatchOptions = .init()
    ) -> [AirportFileMatchResponse] {
        legs.enumerated().map { inputIndex, leg in
            AirportFileMatchResponse(
                inputIndex: inputIndex,
                metadata: leg.metadata,
                match: matchAirports(for: leg.track, options: options)
            )
        }
    }

    private func proximityResponse(
        request: AirportProximityRequest,
        evidence: [AirportCoordinate],
        supportingRadiusKM: Double = 10
    ) -> AirportProximityResponse {
        guard request.coordinate.isValid else {
            return AirportProximityResponse(
                request: request,
                resolution: .invalidCoordinate,
                candidates: []
            )
        }
        guard request.limit > 0,
              request.maximumDistanceKM.isFinite,
              request.maximumDistanceKM > 0 else {
            return AirportProximityResponse(
                request: request,
                resolution: .noMatches,
                candidates: []
            )
        }

        let validEvidence = evidence.filter(\.isValid)
        var ranked: [RankedLocation] = []
        ranked.reserveCapacity(32)
        for record in airports {
            let airportCoordinate = AirportCoordinate(
                latitude: record.airport.latitude,
                longitude: record.airport.longitude
            )
            let distance = geographicDistanceKM(request.coordinate, airportCoordinate)
            guard distance <= request.maximumDistanceKM else { continue }

            var closest = distance
            var supportingPoints = 0
            for observation in validEvidence {
                let observedDistance = geographicDistanceKM(observation, airportCoordinate)
                closest = min(closest, observedDistance)
                if observedDistance <= supportingRadiusKM { supportingPoints += 1 }
            }

            let candidate = AirportProximityCandidate(
                airport: record.airport,
                distanceKM: distance,
                closestObservedDistanceKM: closest,
                supportingPointCount: supportingPoints,
                confidence: locationConfidence(distanceKM: distance)
            )
            let supportBonus = min(Double(max(supportingPoints - 1, 0)) * 0.04, 0.4)
            let scheduledBonus = request.prefersScheduledService
                && record.airport.hasScheduledService ? 0.55 : 0
            let codeBonus = record.airport.iataCode == nil ? 0 : 0.2
            let typeBonus: Double = switch record.airport.type {
            case "large_airport": 0.2
            case "medium_airport": 0.1
            default: 0
            }
            ranked.append(RankedLocation(
                candidate: candidate,
                adjustedDistanceKM: max(
                    0,
                    distance - supportBonus - scheduledBonus - codeBonus - typeBonus
                )
            ))
        }

        ranked.sort {
            if $0.adjustedDistanceKM != $1.adjustedDistanceKM {
                return $0.adjustedDistanceKM < $1.adjustedDistanceKM
            }
            if $0.candidate.distanceKM != $1.candidate.distanceKM {
                return $0.candidate.distanceKM < $1.candidate.distanceKM
            }
            return $0.candidate.airport.id < $1.candidate.airport.id
        }
        let selectedRanks = Array(ranked.prefix(request.limit))
        let candidates = selectedRanks.map(\.candidate)
        guard let first = candidates.first else {
            return AirportProximityResponse(
                request: request,
                resolution: .noMatches,
                candidates: []
            )
        }

        let hasSupport = validEvidence.count <= 1 || first.supportingPointCount >= 2
        let isDecisive: Bool
        if selectedRanks.count < 2 {
            isDecisive = true
        } else {
            // The same bounded operational priors used for ordering may resolve a
            // close commercial-airport/air-base pair, but can never outweigh a
            // two-kilometre ambiguity on their own.
            let margin = selectedRanks[1].adjustedDistanceKM
                - selectedRanks[0].adjustedDistanceKM
            isDecisive = margin >= max(2, first.distanceKM * 0.75)
        }
        let resolution: AirportLocationResolution = first.confidence == .high
            && hasSupport && isDecisive
            ? .automaticSelection
            : .manualSelection
        return AirportProximityResponse(
            request: request,
            resolution: resolution,
            candidates: candidates
        )
    }

    private func endpointEvidence(
        _ track: Track,
        origin: Bool,
        options: AirportTrackMatchOptions
    ) -> [AirportCoordinate] {
        let anchorTime = origin ? track.start.timestamp : track.end.timestamp
        let window = max(0, options.evidenceWindowSeconds)
        let matching = track.points.filter { point in
            origin
                ? point.timestamp - anchorTime <= window
                : anchorTime - point.timestamp <= window
        }
        let ordered = origin ? matching : Array(matching.reversed())
        let maximum = max(1, options.maximumEvidencePoints)
        let points = evenlySample(Array(ordered), limit: maximum)
        return points.map {
            AirportCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func evenlySample(_ points: [TrackPoint], limit: Int) -> [TrackPoint] {
        guard points.count > limit else { return points }
        guard limit > 1 else { return [points[0]] }
        return (0..<limit).map { index in
            let position = Double(index) * Double(points.count - 1) / Double(limit - 1)
            return points[Int(position.rounded())]
        }
    }

    private func locationConfidence(distanceKM: Double) -> AirportLocationConfidence {
        if distanceKM <= 5 { return .high }
        if distanceKM <= 25 { return .medium }
        return .low
    }

    private func rankedResults(
        _ input: String,
        limit: Int,
        policy: SearchPolicy
    ) -> [AirportSearchResult] {
        rankedResults(NormalizedAirportQuery(input), limit: limit, policy: policy)
    }

    private func rankedResults(
        _ query: NormalizedAirportQuery,
        limit: Int,
        policy: SearchPolicy
    ) -> [AirportSearchResult] {
        guard limit > 0 else { return [] }
        guard !query.isEmpty else { return [] }

        let permitFuzzyCode = query.fuzzyCodeCandidate.map {
            policy.allowsFuzzyCode && !indexes.knownCodes.contains($0)
        } ?? false
        let candidates = candidateIndices(
            for: query,
            permitFuzzyCode: permitFuzzyCode,
            policy: policy
        )
        var ranked: [RankedAirport] = []
        ranked.reserveCapacity(candidates.count)
        for index in candidates {
            let record = airports[index]
            guard let result = score(
                record,
                for: query,
                permitFuzzyCode: permitFuzzyCode,
                policy: policy
            )
            else { continue }
            ranked.append(RankedAirport(
                result: result,
                typeRank: airportTypeRank(record.airport.type)
            ))
        }
        ranked.sort(by: rankedBefore)

        guard let first = ranked.first else { return [] }
        let ambiguous = queryIsAmbiguous(ranked)
        return ranked.prefix(limit).map { candidate in
            let nearTop = first.result.score - candidate.result.score <= 80
            let isAmbiguous = ambiguous && (
                nearTop || candidate.result.reasons.contains(.exactCity)
            )
            let confidence: AirportSearchConfidence
            if isAmbiguous, candidate.result.confidence > .medium {
                confidence = .medium
            } else {
                confidence = candidate.result.confidence
            }
            return AirportSearchResult(
                airport: candidate.result.airport,
                score: candidate.result.score,
                reasons: candidate.result.reasons,
                confidence: confidence,
                isAmbiguous: isAmbiguous
            )
        }
    }

    private func candidateIndices(
        for query: NormalizedAirportQuery,
        permitFuzzyCode: Bool,
        policy: SearchPolicy
    ) -> [Int] {
        var candidates: Set<Int> = []
        var protectedCandidates: Set<Int> = []
        for code in query.codeCandidates {
            let matches = indexes.codes[code] ?? []
            candidates.formUnion(matches)
            protectedCandidates.formUnion(matches)
        }
        if permitFuzzyCode, let code = query.fuzzyCodeCandidate {
            for knownCode in indexes.knownCodes where knownCode.count == code.count {
                if airportEditDistance(code, knownCode, limit: 1) == 1 {
                    candidates.formUnion(indexes.codes[knownCode] ?? [])
                }
            }
        }
        var tokenCandidates: Set<Int>?
        for token in query.significantTokens {
            var matches = Set(indexes.words[token] ?? [])
            if token.count >= policy.minimumPrefixLength {
                for term in terms(withPrefix: token, in: indexes.orderedWords) {
                    matches.formUnion(indexes.words[term] ?? [])
                }
            }
            if policy.allowsFuzzyText, allowedTextEdits(for: token) > 0 {
                for term in fuzzyTerms(
                    matching: token,
                    in: indexes.wordsByLength,
                    limit: allowedTextEdits(for: token)
                ) where term != token {
                    matches.formUnion(indexes.words[term] ?? [])
                }
            }
            if let current = tokenCandidates {
                tokenCandidates = current.intersection(matches)
            } else {
                tokenCandidates = matches
            }
        }
        candidates.formUnion(tokenCandidates ?? [])
        let acronymMatches = indexes.acronyms[query.compact] ?? []
        candidates.formUnion(acronymMatches)
        protectedCandidates.formUnion(acronymMatches)
        let compactMatches = indexes.compactFields[query.compact] ?? []
        candidates.formUnion(compactMatches)
        protectedCandidates.formUnion(compactMatches)

        // Compact-field correction is the expensive fallback for merged phrases
        // such as "sanfransisco". Shorter inputs are already covered by word lookup.
        if policy.allowsFuzzyText, query.compact.count >= 10 {
            for compact in fuzzyTerms(
                matching: query.compact,
                in: indexes.compactFieldsByLength,
                limit: allowedPhraseEdits(for: query.compact)
            ) {
                candidates.formUnion(indexes.compactFields[compact] ?? [])
            }
        }

        if let budget = policy.candidateBudget, candidates.count > budget {
            let remaining = candidates.subtracting(protectedCandidates)
                .sorted {
                    let lhsPriority = candidatePriority($0)
                    let rhsPriority = candidatePriority($1)
                    return lhsPriority == rhsPriority
                        ? airports[$0].airport.id < airports[$1].airport.id
                        : lhsPriority > rhsPriority
                }
            candidates = protectedCandidates
            candidates.formUnion(remaining.prefix(max(0, budget - candidates.count)))
        }
        return candidates.sorted()
    }

    private func score(
        _ record: SearchableAirport,
        for query: NormalizedAirportQuery,
        permitFuzzyCode: Bool,
        policy: SearchPolicy
    ) -> AirportSearchResult? {
        var score = 0
        var reasons: [AirportMatchReason] = []
        let phrase = query.significantTokens.joined(separator: " ")

        for code in query.codeCandidates {
            if record.airport.iataCode == code {
                add(1_800, .exactIATA, score: &score, reasons: &reasons)
            }
            if record.airport.icaoCode == code {
                add(1_780, .exactICAO, score: &score, reasons: &reasons)
            }
        }

        addPhraseEvidence(record, phrase: phrase, score: &score, reasons: &reasons)
        addAcronymEvidence(record, compact: query.compact, score: &score, reasons: &reasons)
        addTokenEvidence(
            record,
            tokens: query.significantTokens,
            policy: policy,
            score: &score,
            reasons: &reasons
        )

        let hasDecisiveExactMatch = reasons.contains(.exactIATA)
            || reasons.contains(.exactICAO)
            || reasons.contains(.exactName)
            || reasons.contains(.exactCity)
            || reasons.contains(.exactAlias)
        if !hasDecisiveExactMatch, policy.allowsFuzzyText {
            addFuzzyPhraseEvidence(
                record,
                compactQuery: query.compact,
                score: &score,
                reasons: &reasons
            )
        }

        if score == 0, permitFuzzyCode {
            addFuzzyCodeEvidence(
                record,
                query: query,
                score: &score,
                reasons: &reasons
            )
        }

        guard score >= 500 else { return nil }
        if record.airport.hasScheduledService { score += 12 }
        if record.airport.iataCode != nil { score += 6 }
        score += airportTypeRank(record.airport.type)

        return AirportSearchResult(
            airport: record.airport,
            score: score,
            reasons: reasons,
            confidence: confidence(for: score, reasons: reasons)
        )
    }

    private func addPhraseEvidence(
        _ record: SearchableAirport,
        phrase: String,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard !phrase.isEmpty else { return }
        if phrase == record.name {
            add(1_550, .exactName, score: &score, reasons: &reasons)
        } else if phrase.count >= 3, record.name.hasPrefix(phrase) {
            add(1_050, .namePrefix, score: &score, reasons: &reasons)
        }

        if !record.city.isEmpty {
            if phrase == record.city {
                add(1_400, .exactCity, score: &score, reasons: &reasons)
            } else if phrase.count >= 3, record.city.hasPrefix(phrase) {
                add(980, .cityPrefix, score: &score, reasons: &reasons)
            }
        }

        if record.aliases.contains(phrase) {
            add(1_480, .exactAlias, score: &score, reasons: &reasons)
        } else if phrase.count >= 3,
                  record.aliases.contains(where: { $0.hasPrefix(phrase) }) {
            add(1_020, .aliasPrefix, score: &score, reasons: &reasons)
        }

        if queryCompact(phrase).count >= 5, record.compactFields.contains(queryCompact(phrase)) {
            add(1_250, .exactAlias, score: &score, reasons: &reasons)
        }
    }

    private func addAcronymEvidence(
        _ record: SearchableAirport,
        compact: String,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard compact.count >= 2, record.acronyms.contains(compact) else { return }
        add(1_100, .acronym, score: &score, reasons: &reasons)
    }

    private func addTokenEvidence(
        _ record: SearchableAirport,
        tokens: [String],
        policy: SearchPolicy,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        guard !tokens.isEmpty else { return }
        let evidence = tokens.compactMap {
            bestTokenEvidence($0, record: record, policy: policy)
        }
        guard evidence.count == tokens.count else { return }

        add(
            520 + evidence.reduce(0) { $0 + $1.points },
            .allTerms,
            score: &score,
            reasons: &reasons
        )
        for item in evidence {
            if !reasons.contains(item.reason) { reasons.append(item.reason) }
        }
    }

    private func bestTokenEvidence(
        _ token: String,
        record: SearchableAirport,
        policy: SearchPolicy
    ) -> TokenEvidence? {
        let lowerIATA = record.airport.iataCode?.lowercased()
        let lowerICAO = record.airport.icaoCode?.lowercased()
        if token == lowerIATA || token == lowerICAO {
            return TokenEvidence(points: 220, reason: .tokenMatch)
        }
        if policy.codePrefixPoints > 0,
           token.count >= policy.minimumPrefixLength,
           lowerIATA?.hasPrefix(token) == true || lowerICAO?.hasPrefix(token) == true {
            return TokenEvidence(points: policy.codePrefixPoints, reason: .codePrefix)
        }
        if record.nameWords.contains(token) {
            return TokenEvidence(points: 150 + idfPoints(for: token), reason: .tokenMatch)
        }
        if record.aliasWords.contains(token) {
            return TokenEvidence(points: 145 + idfPoints(for: token), reason: .tokenMatch)
        }
        if record.cityWords.contains(token) {
            return TokenEvidence(points: 140 + idfPoints(for: token), reason: .tokenMatch)
        }
        if token == record.airport.countryCode.lowercased() {
            return TokenEvidence(points: 135, reason: .tokenMatch)
        }
        if record.countryWords.contains(token) {
            return TokenEvidence(points: 110 + idfPoints(for: token), reason: .tokenMatch)
        }

        if token.count >= policy.minimumPrefixLength {
            if let term = bestPrefix(of: token, in: record.nameWords) {
                return TokenEvidence(
                    points: 120 + idfPoints(for: term),
                    reason: .namePrefix
                )
            }
            if let term = bestPrefix(of: token, in: record.aliasWords) {
                return TokenEvidence(
                    points: 115 + idfPoints(for: term),
                    reason: .aliasPrefix
                )
            }
            if let term = bestPrefix(of: token, in: record.cityWords) {
                return TokenEvidence(
                    points: 110 + idfPoints(for: term),
                    reason: .cityPrefix
                )
            }
        }

        guard policy.allowsFuzzyText else { return nil }
        let allowed = allowedTextEdits(for: token)
        guard allowed > 0 else { return nil }
        if let term = bestFuzzyTerm(for: token, in: record.nameWords, limit: allowed) {
            return TokenEvidence(
                points: 110 + idfPoints(for: term),
                reason: .fuzzyName
            )
        }
        if let term = bestFuzzyTerm(for: token, in: record.aliasWords, limit: allowed) {
            return TokenEvidence(
                points: 65 + idfPoints(for: term),
                reason: .fuzzyAlias
            )
        }
        if let term = bestFuzzyTerm(for: token, in: record.cityWords, limit: allowed) {
            return TokenEvidence(
                points: 115 + idfPoints(for: term),
                reason: .fuzzyCity
            )
        }
        return nil
    }

    private func addFuzzyPhraseEvidence(
        _ record: SearchableAirport,
        compactQuery: String,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        let allowed = allowedPhraseEdits(for: compactQuery)
        guard allowed > 0 else { return }
        var best = 0.0
        let fields: [(String, Double)] = [
            (record.cityCompact, 1.08),
            (record.nameCompact, 1.0),
            (record.countryCompact, 0.72),
        ] + record.aliasCompacts.map { ($0, 0.96) }

        for (field, weight) in fields where !field.isEmpty {
            guard abs(field.utf8.count - compactQuery.utf8.count) <= allowed else { continue }
            let distance = airportEditDistance(compactQuery, field, limit: allowed)
            guard distance <= allowed else { continue }
            let similarity = 1 - Double(distance) / Double(max(field.utf8.count, 1))
            best = max(best, similarity * weight)
        }
        guard best >= 0.72 else { return }
        add(360 + Int(min(best, 1.0) * 320), .fuzzyPhrase, score: &score, reasons: &reasons)
    }

    private func addFuzzyCodeEvidence(
        _ record: SearchableAirport,
        query: NormalizedAirportQuery,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        if let code = query.fuzzyCodeCandidate {
            let codes = [record.airport.iataCode, record.airport.icaoCode].compactMap { $0 }
            if codes.contains(where: {
                $0.count == code.count && airportEditDistance(code, $0, limit: 1) == 1
            }) {
                add(540, .fuzzyCode, score: &score, reasons: &reasons)
            }
        }
    }

    private func idfPoints(for term: String) -> Int {
        guard let documentFrequency = indexes.words[term]?.count,
              documentFrequency > 0 else { return 0 }
        let total = Double(airports.count)
        let frequency = Double(documentFrequency)
        let inverseDocumentFrequency = log(
            1 + (total - frequency + 0.5) / (frequency + 0.5)
        )
        return min(80, Int(inverseDocumentFrequency * 10))
    }

    private func bestPrefix(of prefix: String, in words: Set<String>) -> String? {
        words.lazy
            .filter { $0.hasPrefix(prefix) }
            .max {
                let lhsPoints = idfPoints(for: $0)
                let rhsPoints = idfPoints(for: $1)
                return lhsPoints == rhsPoints ? $0 > $1 : lhsPoints < rhsPoints
            }
    }

    private func bestFuzzyTerm(
        for token: String,
        in words: Set<String>,
        limit: Int
    ) -> String? {
        var best: (term: String, distance: Int, idf: Int)?
        for word in words where abs(word.utf8.count - token.utf8.count) <= limit {
            let distance = airportEditDistance(token, word, limit: limit)
            guard distance <= limit else { continue }
            let candidate = (word, distance, idfPoints(for: word))
            if let current = best {
                if candidate.1 < current.distance
                    || candidate.1 == current.distance && candidate.2 > current.idf
                    || candidate.1 == current.distance && candidate.2 == current.idf
                        && candidate.0 < current.term {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best?.term
    }

    private func terms(withPrefix prefix: String, in terms: [String]) -> ArraySlice<String> {
        let start = lowerBound(of: prefix, in: terms)
        var end = start
        while end < terms.count, terms[end].hasPrefix(prefix) { end += 1 }
        return terms[start..<end]
    }

    private func lowerBound(of value: String, in values: [String]) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func fuzzyTerms(
        matching query: String,
        in termsByLength: [Int: [SearchIndexes.IndexedTerm]],
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        let queryBytes = Array(query.utf8)
        let queryMask = characterMask(queryBytes)
        let queryTrigrams = trigramHashes(queryBytes)
        let minimumSharedTrigrams = max(0, queryTrigrams.count - 4 * limit)
        var rows = DistanceRows(capacity: queryBytes.count + limit + 1)
        var matches: [(String, Int)] = []

        let minimumLength = max(1, queryBytes.count - limit)
        let maximumLength = queryBytes.count + limit
        for length in minimumLength...maximumLength {
            guard let terms = termsByLength[length] else { continue }
            for term in terms {
                let missingCharacters = queryMask & ~term.characterMask
                guard missingCharacters.nonzeroBitCount <= limit else { continue }
                if minimumSharedTrigrams > 0,
                   sharedTrigramCount(term.bytes, queryTrigrams) < minimumSharedTrigrams {
                    continue
                }
                let distance = boundedAirportEditDistance(
                    queryBytes,
                    term.bytes,
                    limit: limit,
                    rows: &rows
                )
                if distance <= limit { matches.append((term.value, distance)) }
            }
        }

        matches.sort {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            let lhsIDF = idfPoints(for: $0.0)
            let rhsIDF = idfPoints(for: $1.0)
            return lhsIDF == rhsIDF ? $0.0 < $1.0 : lhsIDF > rhsIDF
        }
        return matches.map(\.0)
    }

    private func candidatePriority(_ index: Int) -> Int {
        let airport = airports[index].airport
        return (airport.hasScheduledService ? 100 : 0)
            + airportTypeRank(airport.type) * 10
            + (airport.iataCode == nil ? 0 : 5)
    }

    private func queryIsAmbiguous(_ ranked: [RankedAirport]) -> Bool {
        guard ranked.count > 1 else { return false }
        let first = ranked[0].result
        let second = ranked[1].result
        if first.reasons.contains(.exactIATA) || first.reasons.contains(.exactICAO) {
            return false
        }
        if first.reasons.contains(.exactCity), second.reasons.contains(.exactCity) {
            return true
        }
        return first.score - second.score <= 30
            && first.confidence == second.confidence
    }

    private func confidence(
        for score: Int,
        reasons: [AirportMatchReason]
    ) -> AirportSearchConfidence {
        if reasons.contains(.exactIATA) || reasons.contains(.exactICAO)
            || reasons.contains(.exactName) || reasons.contains(.exactAlias) {
            return .exact
        }
        if reasons.contains(.exactCity) || score >= 1_250 { return .high }
        if score >= 720 { return .medium }
        return .low
    }

    private func rankedBefore(_ lhs: RankedAirport, _ rhs: RankedAirport) -> Bool {
        let lhsTier = matchTier(lhs.result.reasons)
        let rhsTier = matchTier(rhs.result.reasons)
        if lhsTier != rhsTier { return lhsTier > rhsTier }
        if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
        if lhs.result.airport.hasScheduledService != rhs.result.airport.hasScheduledService {
            return lhs.result.airport.hasScheduledService
        }
        if lhs.typeRank != rhs.typeRank { return lhs.typeRank > rhs.typeRank }
        if (lhs.result.airport.iataCode != nil) != (rhs.result.airport.iataCode != nil) {
            return lhs.result.airport.iataCode != nil
        }
        if lhs.result.airport.name != rhs.result.airport.name {
            return lhs.result.airport.name < rhs.result.airport.name
        }
        return lhs.result.airport.id < rhs.result.airport.id
    }

    /// Match classes are lexicographic, not merely additive. A generic prefix
    /// can accumulate evidence from several duplicated fields, but must never
    /// outrank a real code or a literal field term.
    private func matchTier(_ reasons: [AirportMatchReason]) -> Int {
        if reasons.contains(.exactIATA) || reasons.contains(.exactICAO) { return 6 }
        if reasons.contains(.exactName) || reasons.contains(.exactAlias) { return 5 }
        if reasons.contains(.exactCity) { return 4 }
        if reasons.contains(.tokenMatch) || reasons.contains(.codePrefix) { return 3 }
        if reasons.contains(.acronym) { return 2 }
        return 1
    }

    private func add(
        _ points: Int,
        _ reason: AirportMatchReason,
        score: inout Int,
        reasons: inout [AirportMatchReason]
    ) {
        score += points
        if !reasons.contains(reason) { reasons.append(reason) }
    }

    private func airportTypeRank(_ type: String) -> Int {
        switch type {
        case "large_airport": 4
        case "medium_airport": 3
        case "small_airport": 2
        default: 1
        }
    }

    private static func loadAirports(from url: URL) throws -> [SearchableAirport] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw AirportSearchError("Unable to open airport database: \(message)")
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT a.id, a.ident, a.name, a.country_code, a.municipality,
                   a.iata_code, a.icao_code, a.latitude, a.longitude,
                   a.airport_type, a.scheduled_service, a.keywords, c.name
            FROM airports AS a
            JOIN countries AS c ON c.code = a.country_code
            ORDER BY a.id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AirportSearchError(
                "Unable to read airport database: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        defer { sqlite3_finalize(statement) }

        var records: [SearchableAirport] = []
        records.reserveCapacity(10_000)
        while sqlite3_step(statement) == SQLITE_ROW {
            let airport = Airport(
                id: Int(sqlite3_column_int64(statement, 0)),
                ident: text(statement, 1) ?? "",
                name: text(statement, 2) ?? "",
                countryCode: text(statement, 3) ?? "",
                municipality: text(statement, 4),
                iataCode: text(statement, 5),
                icaoCode: text(statement, 6),
                latitude: sqlite3_column_double(statement, 7),
                longitude: sqlite3_column_double(statement, 8),
                type: text(statement, 9) ?? "",
                hasScheduledService: sqlite3_column_int(statement, 10) == 1,
                countryName: text(statement, 12) ?? ""
            )
            records.append(makeSearchableAirport(
                airport: airport,
                keywords: text(statement, 11) ?? "",
                countryName: text(statement, 12) ?? ""
            ))
        }
        guard sqlite3_errcode(database) == SQLITE_DONE else {
            throw AirportSearchError(
                "Unable to read airport database: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        return records
    }

    private static func makeSearchableAirport(
        airport: Airport,
        keywords: String,
        countryName: String
    ) -> SearchableAirport {
        let name = airportSearchText(airport.name)
        let city = airportSearchText(airport.municipality ?? "")
        let country = airportSearchText(countryName)
        var aliases = keywords.split(separator: ",").map {
            airportSearchText(String($0))
        }.filter { !$0.isEmpty }

        let nameCore = name.split(separator: " ").map(String.init).filter {
            !aliasNoise.contains($0)
        }.joined(separator: " ")
        if !nameCore.isEmpty, nameCore != name { aliases.append(nameCore) }
        if let parenthesis = airport.municipality?.firstIndex(of: "(") {
            let baseCity = airportSearchText(String(airport.municipality?[..<parenthesis] ?? ""))
            if !baseCity.isEmpty, baseCity != city { aliases.append(baseCity) }
        }
        aliases = Array(Set(aliases)).sorted()

        let nameWords = words(name)
        let cityWords = words(city)
        let countryWords = words(country)
        let aliasWords = Set(aliases.flatMap { words($0) })
        let nameCompact = queryCompact(name)
        let cityCompact = queryCompact(city)
        let countryCompact = queryCompact(country)
        let aliasCompacts = aliases.map(queryCompact).filter { !$0.isEmpty }
        let fields = [name, city, country] + aliases
        let compactFields = Set(
            ([nameCompact, cityCompact, countryCompact] + aliasCompacts).filter { !$0.isEmpty }
        )
        let acronyms = Set(fields.compactMap(makeAcronym).filter { $0.count >= 2 })

        return SearchableAirport(
            airport: airport,
            name: name,
            city: city,
            country: country,
            aliases: aliases,
            nameWords: nameWords,
            cityWords: cityWords,
            countryWords: countryWords,
            aliasWords: aliasWords,
            nameCompact: nameCompact,
            cityCompact: cityCompact,
            countryCompact: countryCompact,
            aliasCompacts: aliasCompacts,
            compactFields: compactFields,
            acronyms: acronyms
        )
    }

    private static func makeIndexes(for airports: [SearchableAirport]) -> SearchIndexes {
        var indexes = SearchIndexes()
        for (index, record) in airports.enumerated() {
            let allWords = record.nameWords
                .union(record.cityWords)
                .union(record.countryWords)
                .union(record.aliasWords)
            for word in allWords {
                indexWord(word, airportIndex: index, indexes: &indexes)
            }
            for code in [record.airport.iataCode, record.airport.icaoCode].compactMap({ $0 }) {
                indexes.knownCodes.insert(code)
                append(index, to: code, in: &indexes.codes)
                indexWord(code.lowercased(), airportIndex: index, indexes: &indexes)
            }
            indexWord(
                record.airport.countryCode.lowercased(),
                airportIndex: index,
                indexes: &indexes
            )
            for acronym in record.acronyms {
                append(index, to: acronym, in: &indexes.acronyms)
            }
            for compact in record.compactFields {
                append(index, to: compact, in: &indexes.compactFields)
            }
        }
        indexes.orderedWords = indexes.words.keys.sorted()
        indexes.wordsByLength = makeLengthIndex(indexes.words.keys)
        indexes.compactFieldsByLength = makeLengthIndex(indexes.compactFields.keys)
        return indexes
    }

    private static func makeLengthIndex(
        _ values: Dictionary<String, [Int]>.Keys
    ) -> [Int: [SearchIndexes.IndexedTerm]] {
        var result: [Int: [SearchIndexes.IndexedTerm]] = [:]
        for value in values {
            let bytes = Array(value.utf8)
            result[bytes.count, default: []].append(SearchIndexes.IndexedTerm(
                value: value,
                bytes: bytes,
                characterMask: characterMask(bytes)
            ))
        }
        for length in result.keys {
            result[length]?.sort { $0.value < $1.value }
        }
        return result
    }

    private static func indexWord(
        _ word: String,
        airportIndex: Int,
        indexes: inout SearchIndexes
    ) {
        append(airportIndex, to: word, in: &indexes.words)
    }

    private static func append(
        _ index: Int,
        to key: String,
        in dictionary: inout [String: [Int]]
    ) {
        if dictionary[key]?.last != index {
            dictionary[key, default: []].append(index)
        }
    }

    private static func words(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private static func makeAcronym(_ value: String) -> String? {
        let initials = value.split(separator: " ").compactMap { word -> Character? in
            let text = String(word)
            guard !acronymNoise.contains(text) else { return nil }
            return text.first
        }
        return initials.isEmpty ? nil : String(initials)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}

private func queryCompact(_ value: String) -> String {
    value.filter { $0.isASCII && $0.isLetter || $0.isNumber }
}

private func allowedTextEdits(for word: String) -> Int {
    if word.count >= 9 { return 2 }
    if word.count >= 4 { return 1 }
    return 0
}

private func allowedPhraseEdits(for value: String) -> Int {
    if value.utf8.count >= 13 { return 3 }
    if value.utf8.count >= 8 { return 2 }
    if value.utf8.count >= 4 { return 1 }
    return 0
}

private struct DistanceRows {
    var previousPrevious: [Int]
    var previous: [Int]
    var current: [Int]

    init(capacity: Int) {
        previousPrevious = Array(repeating: 0, count: capacity)
        previous = Array(repeating: 0, count: capacity)
        current = Array(repeating: 0, count: capacity)
    }

    mutating func ensureCapacity(_ capacity: Int) {
        guard previous.count < capacity else { return }
        previousPrevious = Array(repeating: 0, count: capacity)
        previous = Array(repeating: 0, count: capacity)
        current = Array(repeating: 0, count: capacity)
    }
}

func airportEditDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
    if lhs == rhs { return 0 }
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var rows = DistanceRows(capacity: right.count + 1)
    return boundedAirportEditDistance(left, right, limit: limit, rows: &rows)
}

private func boundedAirportEditDistance(
    _ left: [UInt8],
    _ right: [UInt8],
    limit: Int,
    rows: inout DistanceRows
) -> Int {
    if left == right { return 0 }
    if abs(left.count - right.count) > limit { return limit + 1 }
    if left.isEmpty { return min(right.count, limit + 1) }
    if right.isEmpty { return min(left.count, limit + 1) }

    rows.ensureCapacity(right.count + 1)
    for index in 0...right.count {
        rows.previousPrevious[index] = index
        rows.previous[index] = index
        rows.current[index] = limit + 1
    }

    for leftIndex in 1...left.count {
        rows.current[0] = leftIndex
        var rowMinimum = limit + 1
        for rightIndex in 1...right.count {
            let substitution = rows.previous[rightIndex - 1]
                + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1)
            var value = min(
                rows.previous[rightIndex] + 1,
                rows.current[rightIndex - 1] + 1,
                substitution
            )
            if leftIndex > 1, rightIndex > 1,
               left[leftIndex - 1] == right[rightIndex - 2],
               left[leftIndex - 2] == right[rightIndex - 1] {
                value = min(value, rows.previousPrevious[rightIndex - 2] + 1)
            }
            rows.current[rightIndex] = value
            rowMinimum = min(rowMinimum, value)
        }
        if rowMinimum > limit { return limit + 1 }
        swap(&rows.previousPrevious, &rows.previous)
        swap(&rows.previous, &rows.current)
    }
    return rows.previous[right.count]
}

private func characterMask(_ bytes: [UInt8]) -> UInt32 {
    bytes.reduce(into: UInt32(0)) { mask, byte in
        mask |= UInt32(1) << UInt32(byte & 31)
    }
}

private func trigramHashes(_ bytes: [UInt8]) -> Set<UInt32> {
    guard bytes.count >= 3 else { return [] }
    var result: Set<UInt32> = []
    result.reserveCapacity(bytes.count - 2)
    for index in 0...(bytes.count - 3) {
        let first = UInt32(bytes[index]) << 16
        let second = UInt32(bytes[index + 1]) << 8
        result.insert(first | second | UInt32(bytes[index + 2]))
    }
    return result
}

private func sharedTrigramCount(_ bytes: [UInt8], _ query: Set<UInt32>) -> Int {
    guard bytes.count >= 3, !query.isEmpty else { return 0 }
    var shared = 0
    for index in 0...(bytes.count - 3) {
        let first = UInt32(bytes[index]) << 16
        let second = UInt32(bytes[index + 1]) << 8
        let hash = first | second | UInt32(bytes[index + 2])
        if query.contains(hash) { shared += 1 }
    }
    return shared
}

private func geographicDistanceKM(
    _ first: AirportCoordinate,
    _ second: AirportCoordinate
) -> Double {
    let latitude1 = first.latitude * .pi / 180
    let longitude1 = first.longitude * .pi / 180
    let latitude2 = second.latitude * .pi / 180
    let longitude2 = second.longitude * .pi / 180
    let latitudeDelta = latitude2 - latitude1
    let longitudeDelta = longitude2 - longitude1
    let haversine = pow(sin(latitudeDelta / 2), 2)
        + cos(latitude1) * cos(latitude2) * pow(sin(longitudeDelta / 2), 2)
    return 6_371.0088 * 2 * asin(min(1, sqrt(haversine)))
}
