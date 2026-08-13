import Foundation

public struct AirportCoordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

public struct AirportProximityRequest: Sendable, Equatable {
    public let coordinate: AirportCoordinate
    public let limit: Int
    public let maximumDistanceKM: Double
    public let prefersScheduledService: Bool

    public init(
        coordinate: AirportCoordinate,
        limit: Int = 5,
        maximumDistanceKM: Double = 100,
        prefersScheduledService: Bool = true
    ) {
        self.coordinate = coordinate
        self.limit = limit
        self.maximumDistanceKM = maximumDistanceKM
        self.prefersScheduledService = prefersScheduledService
    }

    public var hasValidParameters: Bool {
        limit > 0 && maximumDistanceKM.isFinite && maximumDistanceKM > 0
    }
}

public enum AirportLocationConfidence: String, Sendable, Equatable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct AirportProximityCandidate: Sendable, Equatable, Identifiable {
    public let airport: Airport
    public let distanceKM: Double
    public let closestObservedDistanceKM: Double
    public let supportingPointCount: Int
    public let confidence: AirportLocationConfidence

    public var id: Int { airport.id }

    public init(
        airport: Airport,
        distanceKM: Double,
        closestObservedDistanceKM: Double,
        supportingPointCount: Int,
        confidence: AirportLocationConfidence
    ) {
        self.airport = airport
        self.distanceKM = distanceKM
        self.closestObservedDistanceKM = closestObservedDistanceKM
        self.supportingPointCount = supportingPointCount
        self.confidence = confidence
    }
}

public enum AirportLocationResolution: String, Sendable, Equatable, CaseIterable {
    case invalidCoordinate
    case invalidRequest
    case noMatches
    case manualSelection
    case automaticSelection
}

public struct AirportProximityResponse: Sendable, Equatable {
    public let request: AirportProximityRequest
    public let resolution: AirportLocationResolution
    public let candidates: [AirportProximityCandidate]

    public init(
        request: AirportProximityRequest,
        resolution: AirportLocationResolution,
        candidates: [AirportProximityCandidate]
    ) {
        self.request = request
        self.resolution = resolution
        self.candidates = candidates
    }

    public var automaticSelection: AirportProximityCandidate? {
        resolution == .automaticSelection ? candidates.first : nil
    }
}

public struct AirportTrackMatchOptions: Sendable, Equatable {
    public let limit: Int
    public let maximumDistanceKM: Double
    public let evidenceWindowSeconds: Double
    public let maximumEvidencePoints: Int
    public let supportingRadiusKM: Double
    public let prefersScheduledService: Bool

    public init(
        limit: Int = 5,
        maximumDistanceKM: Double = 100,
        evidenceWindowSeconds: Double = 10 * 60,
        maximumEvidencePoints: Int = 64,
        supportingRadiusKM: Double = 10,
        prefersScheduledService: Bool = true
    ) {
        self.limit = limit
        self.maximumDistanceKM = maximumDistanceKM
        self.evidenceWindowSeconds = evidenceWindowSeconds
        self.maximumEvidencePoints = maximumEvidencePoints
        self.supportingRadiusKM = supportingRadiusKM
        self.prefersScheduledService = prefersScheduledService
    }

    public var isValid: Bool {
        limit > 0
            && maximumDistanceKM.isFinite && maximumDistanceKM > 0
            && evidenceWindowSeconds.isFinite && evidenceWindowSeconds >= 0
            && maximumEvidencePoints > 0
            && supportingRadiusKM.isFinite && supportingRadiusKM >= 0
    }
}

public struct AirportTrackMatchResponse: Sendable, Equatable {
    public let origin: AirportProximityResponse
    public let destination: AirportProximityResponse

    public init(
        origin: AirportProximityResponse,
        destination: AirportProximityResponse
    ) {
        self.origin = origin
        self.destination = destination
    }

    public var automaticOrigin: AirportProximityCandidate? {
        origin.automaticSelection
    }

    public var automaticDestination: AirportProximityCandidate? {
        destination.automaticSelection
    }
}

public struct AirportFileMatchResponse: Sendable, Equatable, Identifiable {
    /// Stable within one input batch, even if the same URL appears more than once.
    public let inputIndex: Int
    /// The source of the track that was actually analyzed.
    public let source: URL
    public let metadata: FR24Metadata
    public let match: AirportTrackMatchResponse

    public var id: Int { inputIndex }
    public init(
        inputIndex: Int,
        source: URL,
        metadata: FR24Metadata,
        match: AirportTrackMatchResponse
    ) {
        self.inputIndex = inputIndex
        self.source = source
        self.metadata = metadata
        self.match = match
    }
}
