import Foundation

public struct Point2D: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MapViewport: Equatable, Sendable {
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// The geographic bounds mapped into the fixed map viewport.
public struct MapProjection: Equatable, Sendable {
    public let minimumLongitude: Double
    public let maximumLongitude: Double
    public let minimumLatitude: Double
    public let maximumLatitude: Double

    public init(
        minimumLongitude: Double,
        maximumLongitude: Double,
        minimumLatitude: Double,
        maximumLatitude: Double
    ) {
        precondition(maximumLongitude > minimumLongitude)
        precondition(maximumLatitude > minimumLatitude)
        self.minimumLongitude = minimumLongitude
        self.maximumLongitude = maximumLongitude
        self.minimumLatitude = minimumLatitude
        self.maximumLatitude = maximumLatitude
    }

    public var centerLongitude: Double {
        (minimumLongitude + maximumLongitude) / 2
    }
}

public enum AeroRouteGeometry {
    /// The flat-map drawing bounds used by the reference renderer.
    ///
    /// The longitude range is pinned to the full canvas width. Antarctica is
    /// intentionally outside the visible latitude range so that the lower
    /// ocean area remains available for editorial metadata.
    public static func mapViewport(width: Double, height: Double) -> MapViewport {
        MapViewport(
            left: 0,
            top: height * 0.19,
            right: width,
            bottom: height * 0.82
        )
    }

    /// Projects WGS84 coordinates onto AeroRoute's flat equirectangular map.
    public static func project(
        longitude: Double,
        latitude: Double,
        width: Double,
        height: Double
    ) -> Point2D {
        let viewport = mapViewport(width: width, height: height)
        let x = viewport.left
            + (longitude + 180) / 360 * (viewport.right - viewport.left)
        let latitudeMaximum = 85.0
        let latitudeMinimum = -60.0
        let y = viewport.top
            + (latitudeMaximum - latitude) / (latitudeMaximum - latitudeMinimum)
            * (viewport.bottom - viewport.top)
        return Point2D(x: x, y: y)
    }

    /// Projects WGS84 coordinates into a caller-provided geographic region.
    public static func project(
        longitude: Double,
        latitude: Double,
        width: Double,
        height: Double,
        projection: MapProjection,
        viewport: MapViewport? = nil
    ) -> Point2D {
        let viewport = viewport ?? mapViewport(width: width, height: height)
        let x = viewport.left
            + (longitude - projection.minimumLongitude)
            / (projection.maximumLongitude - projection.minimumLongitude)
            * (viewport.right - viewport.left)
        let y = viewport.top
            + (projection.maximumLatitude - latitude)
            / (projection.maximumLatitude - projection.minimumLatitude)
            * (viewport.bottom - viewport.top)
        return Point2D(x: x, y: y)
    }

    /// Builds an aspect-fitted region around a flight track with editorial
    /// breathing room. Longitudes are unwrapped before measuring the bounds.
    public static func routeFittingProjection(
        coordinates: [(longitude: Double, latitude: Double)],
        width: Double,
        height: Double,
        viewport: MapViewport? = nil,
        paddingFraction: Double = 0.08
    ) -> MapProjection {
        precondition(!coordinates.isEmpty)
        precondition(width > 0 && height > 0)
        precondition(paddingFraction >= 0)

        let unwrapped = unwrapLongitudes(coordinates)
        let longitudes = unwrapped.map(\.longitude)
        let latitudes = unwrapped.map(\.latitude)
        let longitudeCenter = (longitudes.min()! + longitudes.max()!) / 2
        let latitudeCenter = (latitudes.min()! + latitudes.max()!) / 2
        var longitudeSpan = max(longitudes.max()! - longitudes.min()!, 2)
        var latitudeSpan = max(latitudes.max()! - latitudes.min()!, 2)

        let paddingScale = 1 + paddingFraction * 2
        longitudeSpan *= paddingScale
        latitudeSpan *= paddingScale

        let viewport = viewport ?? mapViewport(width: width, height: height)
        let viewportAspect = (viewport.right - viewport.left)
            / (viewport.bottom - viewport.top)
        if longitudeSpan / latitudeSpan < viewportAspect {
            longitudeSpan = latitudeSpan * viewportAspect
        } else {
            latitudeSpan = longitudeSpan / viewportAspect
        }

        return MapProjection(
            minimumLongitude: longitudeCenter - longitudeSpan / 2,
            maximumLongitude: longitudeCenter + longitudeSpan / 2,
            minimumLatitude: latitudeCenter - latitudeSpan / 2,
            maximumLatitude: latitudeCenter + latitudeSpan / 2
        )
    }

    /// Returns the equivalent longitude nearest the projection center.
    public static func longitudeNearestProjectionCenter(
        _ longitude: Double,
        projection: MapProjection
    ) -> Double {
        longitude + (360 * ((projection.centerLongitude - longitude) / 360).rounded())
    }

    /// Keeps adjacent longitudes continuous when a track crosses the
    /// antimeridian. Values outside -180...180 are deliberate: the SVG
    /// renderer draws shifted copies of the resulting path at the map edges.
    public static func unwrapLongitudes(
        _ coordinates: [(longitude: Double, latitude: Double)]
    ) -> [(longitude: Double, latitude: Double)] {
        var unwrapped: [(longitude: Double, latitude: Double)] = []
        unwrapped.reserveCapacity(coordinates.count)

        var previous: Double?
        for coordinate in coordinates {
            var candidate = coordinate.longitude
            if let previous {
                while candidate - previous > 180 {
                    candidate -= 360
                }
                while candidate - previous < -180 {
                    candidate += 360
                }
            }
            unwrapped.append((candidate, coordinate.latitude))
            previous = candidate
        }
        return unwrapped
    }

    /// Matches Python's `f"{value:.6f}".rstrip("0").rstrip(".")` output.
    public static func formatCoordinate(_ value: Double) -> String {
        var text = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text == "-0" || text.isEmpty ? "0" : text
    }

    /// Creates one centripetal Catmull-Rom-derived cubic segment between each
    /// pair of source points. The curve passes through every input point.
    public static func interpolatingBezierPath(
        _ points: [Point2D]
    ) -> (path: String, segments: Int) {
        precondition(points.count >= 2, "at least two points are required")

        var knots = [0.0]
        knots.reserveCapacity(points.count)
        for (current, following) in zip(points, points.dropFirst()) {
            let distance = hypot(following.x - current.x, following.y - current.y)
            knots.append(knots[knots.count - 1] + max(sqrt(distance), 1e-6))
        }

        var tangents: [Point2D] = []
        tangents.reserveCapacity(points.count)
        for index in points.indices {
            let point = points[index]
            let tangent: Point2D
            if index == points.startIndex {
                let delta = knots[1] - knots[0]
                tangent = Point2D(
                    x: (points[1].x - point.x) / delta,
                    y: (points[1].y - point.y) / delta
                )
            } else if index == points.index(before: points.endIndex) {
                let delta = knots[knots.count - 1] - knots[knots.count - 2]
                tangent = Point2D(
                    x: (point.x - points[points.count - 2].x) / delta,
                    y: (point.y - points[points.count - 2].y) / delta
                )
            } else {
                let delta = knots[index + 1] - knots[index - 1]
                tangent = Point2D(
                    x: (points[index + 1].x - points[index - 1].x) / delta,
                    y: (points[index + 1].y - points[index - 1].y) / delta
                )
            }
            tangents.append(tangent)
        }

        var commands = [
            "M \(formatCoordinate(points[0].x)) \(formatCoordinate(points[0].y))"
        ]
        commands.reserveCapacity(points.count)

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let interval = knots[index + 1] - knots[index]
            let control1 = Point2D(
                x: start.x + tangents[index].x * interval / 3,
                y: start.y + tangents[index].y * interval / 3
            )
            let control2 = Point2D(
                x: end.x - tangents[index + 1].x * interval / 3,
                y: end.y - tangents[index + 1].y * interval / 3
            )
            commands.append(
                "C \(formatCoordinate(control1.x)) \(formatCoordinate(control1.y)) "
                    + "\(formatCoordinate(control2.x)) \(formatCoordinate(control2.y)) "
                    + "\(formatCoordinate(end.x)) \(formatCoordinate(end.y))"
            )
        }

        return (commands.joined(separator: " "), points.count - 1)
    }

    /// Converts a GeoJSON Polygon or MultiPolygon into SVG path commands.
    public static func geoJSONPath(
        geometry: GeoJSONGeometry,
        width: Double,
        height: Double
    ) -> String {
        let polygons: [GeoJSONPolygonCoordinates]
        switch geometry {
        case .polygon(let coordinates):
            polygons = [coordinates]
        case .multiPolygon(let coordinates):
            polygons = coordinates
        case .unsupported:
            return ""
        }

        var commands: [String] = []
        for polygon in polygons {
            for ring in polygon where !ring.isEmpty {
                let projected = ring.map {
                    project(
                        longitude: $0.longitude,
                        latitude: $0.latitude,
                        width: width,
                        height: height
                    )
                }
                guard let first = projected.first else { continue }
                commands.append(
                    "M \(formatCoordinate(first.x)) \(formatCoordinate(first.y))"
                )
                commands.append(contentsOf: projected.dropFirst().map {
                    "L \(formatCoordinate($0.x)) \(formatCoordinate($0.y))"
                })
                commands.append("Z")
            }
        }
        return commands.joined(separator: " ")
    }

    /// Converts GeoJSON into a path for a focused projection, moving each
    /// complete ring to the world copy nearest the flight.
    public static func geoJSONPath(
        geometry: GeoJSONGeometry,
        width: Double,
        height: Double,
        projection: MapProjection,
        viewport: MapViewport? = nil
    ) -> String {
        let polygons: [GeoJSONPolygonCoordinates]
        switch geometry {
        case .polygon(let coordinates):
            polygons = [coordinates]
        case .multiPolygon(let coordinates):
            polygons = coordinates
        case .unsupported:
            return ""
        }

        var commands: [String] = []
        for polygon in polygons {
            for ring in polygon where !ring.isEmpty {
                let coordinates = unwrapLongitudes(
                    ring.map { ($0.longitude, $0.latitude) }
                )
                let ringCenter = coordinates.map(\.longitude).reduce(0, +)
                    / Double(coordinates.count)
                let shift = longitudeNearestProjectionCenter(
                    ringCenter,
                    projection: projection
                ) - ringCenter
                let projected = coordinates.map {
                    project(
                        longitude: $0.longitude + shift,
                        latitude: $0.latitude,
                        width: width,
                        height: height,
                        projection: projection,
                        viewport: viewport
                    )
                }
                guard let first = projected.first else { continue }
                commands.append(
                    "M \(formatCoordinate(first.x)) \(formatCoordinate(first.y))"
                )
                commands.append(contentsOf: projected.dropFirst().map {
                    "L \(formatCoordinate($0.x)) \(formatCoordinate($0.y))"
                })
                commands.append("Z")
            }
        }
        return commands.joined(separator: " ")
    }
}
