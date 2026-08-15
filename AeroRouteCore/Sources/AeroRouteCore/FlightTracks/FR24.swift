import Foundation

public let fr24RequiredColumns: Set<String> = [
    "Timestamp", "UTC", "Callsign", "Position",
]

public let fr24OptionalColumns: Set<String> = [
    "Altitude", "Speed", "Direction",
]

public struct FR24CSVAdapter: Sendable {
    public init() {}

    public static func recognizes(_ fieldnames: [String]?) -> Bool {
        fr24RequiredColumns.isSubset(of: Set(fieldnames ?? []))
    }

    public func load(_ source: URL) throws -> ImportedLeg {
        let document = try CSVDocument(data: Data(contentsOf: source))
        let fieldnames = document.rows.first
        guard Self.recognizes(fieldnames) else {
            let missing = fr24RequiredColumns
                .subtracting(Set(fieldnames ?? []))
                .sorted()
                .joined(separator: ", ")
            throw TrackDataError(
                "not a standard Flightradar24 CSV; missing columns: \(missing)"
            )
        }

        let headers = fieldnames ?? []
        var indexedPoints: [(offset: Int, point: TrackPoint)] = []
        var recordNumber = 1
        for fields in document.rows.dropFirst() {
            // DictReader skips physically blank rows, but not rows containing fields.
            guard !fields.isEmpty else { continue }
            recordNumber += 1
            let rowNumber = recordNumber
            let row = CSVRecord(headers: headers, fields: fields)

            guard let timestampValue = row["Timestamp"],
                  let timestamp = parseDouble(timestampValue) else {
                throw TrackDataError(
                    "row \(rowNumber): invalid Timestamp: \(pythonRepr(row["Timestamp"]))"
                )
            }

            let positionValue = row["Position"] ?? ""
            let position = positionValue.split(
                separator: ",",
                maxSplits: .max,
                omittingEmptySubsequences: false
            )
            guard position.count == 2 else {
                throw TrackDataError(
                    "row \(rowNumber): Position must be 'latitude,longitude'"
                )
            }
            guard let latitude = parseDouble(String(position[0])),
                  let longitude = parseDouble(String(position[1])) else {
                throw TrackDataError(
                    "row \(rowNumber): invalid Position: \(pythonRepr(row["Position"]))"
                )
            }
            guard latitude >= -90, latitude <= 90 else {
                throw TrackDataError("row \(rowNumber): latitude out of range")
            }
            guard longitude >= -180, longitude <= 180 else {
                throw TrackDataError("row \(rowNumber): longitude out of range")
            }

            let point = TrackPoint(
                timestamp: timestamp,
                utc: try parseUTC(row["UTC"], timestamp: timestamp, rowNumber: rowNumber),
                callsign: (row["Callsign"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: latitude,
                longitude: longitude,
                altitude: try optionalDouble(
                    row["Altitude"], rowNumber: rowNumber, field: "Altitude"
                ),
                speed: try optionalDouble(
                    row["Speed"], rowNumber: rowNumber, field: "Speed"
                ),
                direction: try optionalDouble(
                    row["Direction"], rowNumber: rowNumber, field: "Direction"
                )
            )
            indexedPoints.append((recordNumber, point))
        }

        guard indexedPoints.count >= 2 else {
            throw TrackDataError("at least two FR24 positions are required")
        }
        indexedPoints.sort {
            if $0.point.timestamp == $1.point.timestamp {
                return $0.offset < $1.offset
            }
            return $0.point.timestamp < $1.point.timestamp
        }
        let points = indexedPoints.map(\.point)
        let track = Track(
            source: source,
            points: points,
            waypointIndices: [0, points.count - 1]
        )
        return ImportedLeg(
            track: track,
            metadata: FR24Metadata(
                source: source,
                flightNumber: flightNumberFromFilename(source),
                callsign: track.callsign,
                rowCount: points.count
            )
        )
    }

    public func load(_ path: String) throws -> ImportedLeg {
        try load(URL(fileURLWithPath: path))
    }
}

public func loadFR24(_ source: URL) throws -> ImportedLeg {
    try FR24CSVAdapter().load(source)
}

public func loadFR24(_ path: String) throws -> ImportedLeg {
    try FR24CSVAdapter().load(path)
}

public func loadTrack(_ source: URL) throws -> Track {
    try loadFR24(source).track
}

public func loadTrack(_ path: String) throws -> Track {
    try loadFR24(path).track
}

public func flightNumberFromFilename(_ source: URL) -> String {
    let stem = source.deletingPathExtension().lastPathComponent
    let prefix = stem.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        .first
        .map(String.init) ?? ""
    let candidate = prefix.uppercased().replacingOccurrences(of: " ", with: "")
    let range = candidate.range(
        of: #"^[A-Z0-9]{2,3}\d{1,4}[A-Z]?$"#,
        options: .regularExpression
    )
    return range == candidate.startIndex..<candidate.endIndex ? candidate : stem
}

public func flightNumberFromFilename(_ path: String) -> String {
    flightNumberFromFilename(URL(fileURLWithPath: path))
}

public func endpointDistanceKM(_ first: Track, _ second: Track) -> Double {
    let lat1 = first.end.latitude * .pi / 180
    let lon1 = first.end.longitude * .pi / 180
    let lat2 = second.start.latitude * .pi / 180
    let lon2 = second.start.longitude * .pi / 180
    let dlat = lat2 - lat1
    let dlon = lon2 - lon1
    let value = pow(sin(dlat / 2), 2)
        + cos(lat1) * cos(lat2) * pow(sin(dlon / 2), 2)
    return 6_371.0088 * 2 * asin(sqrt(value))
}

public func validateLegOrder(
    _ tracks: [Track],
    toleranceKM: Double = 50
) throws -> [Double] {
    if toleranceKM <= 0 {
        throw TrackDataError("continuity tolerance must be greater than zero")
    }
    var distances: [Double] = []
    for index in 0..<max(tracks.count - 1, 0) {
        let distance = endpointDistanceKM(tracks[index], tracks[index + 1])
        distances.append(distance)
        if distance > toleranceKM {
            let formatted = String(
                format: "%.1f",
                locale: Locale(identifier: "en_US_POSIX"),
                distance
            )
            throw TrackDataError(
                "leg \(index + 1) does not connect to leg \(index + 2): "
                    + "end-to-start distance is \(formatted) km"
            )
        }
    }
    return distances
}

public func combineTracks(
    paths: [URL],
    sourceName: String = "itinerary",
    validateContinuity: Bool = false,
    toleranceKM: Double = 50
) throws -> Track {
    guard !paths.isEmpty else {
        throw TrackDataError("at least one ADS-B CSV file is required")
    }
    let tracks = try paths.map(loadTrack)
    return try combineTracks(
        tracks: tracks,
        source: URL(fileURLWithPath: sourceName),
        validateContinuity: validateContinuity,
        toleranceKM: toleranceKM
    )
}

public func combineTracks(
    paths: [String],
    sourceName: String = "itinerary",
    validateContinuity: Bool = false,
    toleranceKM: Double = 50
) throws -> Track {
    try combineTracks(
        paths: paths.map { URL(fileURLWithPath: $0) },
        sourceName: sourceName,
        validateContinuity: validateContinuity,
        toleranceKM: toleranceKM
    )
}

public func combineTracks(
    tracks: [Track],
    source: URL = URL(fileURLWithPath: "itinerary"),
    validateContinuity: Bool = false,
    toleranceKM: Double = 50
) throws -> Track {
    guard !tracks.isEmpty else {
        throw TrackDataError("at least one ADS-B CSV file is required")
    }
    if validateContinuity {
        _ = try validateLegOrder(tracks, toleranceKM: toleranceKM)
    }

    var points: [TrackPoint] = []
    var waypointIndices = [0]
    var pathStartIndices = [0]
    for (index, track) in tracks.enumerated() {
        if index > 0 {
            let connects = endpointDistanceKM(tracks[index - 1], track) <= toleranceKM
            if !connects {
                pathStartIndices.append(points.count)
                waypointIndices.append(points.count)
            }
        }
        points.append(contentsOf: track.points)
        waypointIndices.append(points.count - 1)
    }
    return Track(
        source: source,
        points: points,
        waypointIndices: waypointIndices,
        pathStartIndices: pathStartIndices
    )
}

private func parseDouble(_ value: String) -> Double? {
    Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func optionalDouble(
    _ value: String?,
    rowNumber: Int,
    field: String
) throws -> Double? {
    guard let value else { return nil }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    guard let number = parseDouble(value) else {
        throw TrackDataError(
            "row \(rowNumber): invalid \(field): \(pythonRepr(value))"
        )
    }
    return number
}

private func parseUTC(
    _ value: String?,
    timestamp: Double,
    rowNumber: Int
) throws -> Date {
    guard let value,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return Date(timeIntervalSince1970: timestamp)
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formats = [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(includingFractionalSeconds: false),
    ]
    for format in formats {
        if let date = try? format.parse(trimmed) {
            return date
        }
    }
    throw TrackDataError("row \(rowNumber): invalid UTC: \(pythonRepr(value))")
}

private func pythonRepr(_ value: String?) -> String {
    guard let value else { return "None" }
    let usesDoubleQuotes = value.contains("'") && !value.contains("\"")
    let quote: Character = usesDoubleQuotes ? "\"" : "'"
    var result = String(quote)
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x09: result += "\\t"
        case 0x0A: result += "\\n"
        case 0x0D: result += "\\r"
        case 0x5C: result += "\\\\"
        case UInt32(quote.asciiValue ?? 0): result += "\\" + String(quote)
        case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F:
            result += String(format: "\\x%02x", scalar.value)
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    result.append(quote)
    return result
}
