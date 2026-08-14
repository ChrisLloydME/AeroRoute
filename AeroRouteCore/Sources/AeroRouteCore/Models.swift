import Foundation

/// A single, unsampled position from a Flightradar24 flight-track export.
public struct TrackPoint: Sendable, Equatable {
    public let timestamp: Double
    public let utc: Date
    public let callsign: String
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let speed: Double?
    public let direction: Double?

    public init(
        timestamp: Double,
        utc: Date,
        callsign: String,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        speed: Double?,
        direction: Double?
    ) {
        self.timestamp = timestamp
        self.utc = utc
        self.callsign = callsign
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.direction = direction
    }
}

/// An ordered flight track. Points are kept exactly as imported, including repeats.
public struct Track: Sendable, Equatable {
    public let source: URL
    public let points: [TrackPoint]
    public let waypointIndices: [Int]
    /// Point indices that begin a new, visually disconnected route path.
    public let pathStartIndices: [Int]

    public init(
        source: URL,
        points: [TrackPoint],
        waypointIndices: [Int] = [],
        pathStartIndices: [Int] = []
    ) {
        self.source = source
        self.points = points
        self.waypointIndices = waypointIndices
        self.pathStartIndices = pathStartIndices
    }

    public var callsign: String {
        points.first(where: { !$0.callsign.isEmpty })?.callsign ?? ""
    }

    public var start: TrackPoint { points[0] }

    public var end: TrackPoint { points[points.count - 1] }

    public var waypoints: [TrackPoint] {
        let indices = waypointIndices.isEmpty ? [0, points.count - 1] : waypointIndices
        return indices.map { points[$0] }
    }

    public var pathRanges: [Range<Int>] {
        let starts = pathStartIndices.isEmpty ? [0] : pathStartIndices
        return starts.enumerated().compactMap { offset, start in
            let end = offset + 1 < starts.count ? starts[offset + 1] : points.count
            return start >= 0 && start < end && end <= points.count ? start..<end : nil
        }
    }
}

public struct FR24Metadata: Sendable, Equatable {
    public let source: URL
    public let flightNumber: String
    public let callsign: String
    public let rowCount: Int

    public init(source: URL, flightNumber: String, callsign: String, rowCount: Int) {
        self.source = source
        self.flightNumber = flightNumber
        self.callsign = callsign
        self.rowCount = rowCount
    }
}

public struct ImportedLeg: Sendable, Equatable {
    public let track: Track
    public let metadata: FR24Metadata

    public init(track: Track, metadata: FR24Metadata) {
        self.track = track
        self.metadata = metadata
    }
}

/// A user-presentable error produced when an ADS-B row cannot be represented safely.
public struct TrackDataError: Error, LocalizedError, CustomStringConvertible, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public var description: String { message }
}
