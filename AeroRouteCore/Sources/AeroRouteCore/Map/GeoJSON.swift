import Foundation

public struct GeoJSONPosition: Decodable, Equatable, Sendable {
    public let longitude: Double
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Double.self)
        latitude = try container.decode(Double.self)
    }
}

public typealias GeoJSONLinearRing = [GeoJSONPosition]
public typealias GeoJSONPolygonCoordinates = [GeoJSONLinearRing]
public typealias GeoJSONMultiPolygonCoordinates = [GeoJSONPolygonCoordinates]

public enum GeoJSONGeometry: Decodable, Equatable, Sendable {
    case polygon(GeoJSONPolygonCoordinates)
    case multiPolygon(GeoJSONMultiPolygonCoordinates)
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Polygon":
            self = .polygon(
                try container.decode(GeoJSONPolygonCoordinates.self, forKey: .coordinates)
            )
        case "MultiPolygon":
            self = .multiPolygon(
                try container.decode(
                    GeoJSONMultiPolygonCoordinates.self,
                    forKey: .coordinates
                )
            )
        default:
            self = .unsupported(type: type)
        }
    }
}

public struct GeoJSONProperties: Decodable, Equatable, Sendable {
    public let labelX: Double?
    public let labelY: Double?
    public let name: String?
    public let labelRank: Int?

    public init(
        labelX: Double? = nil,
        labelY: Double? = nil,
        name: String? = nil,
        labelRank: Int? = nil
    ) {
        self.labelX = labelX
        self.labelY = labelY
        self.name = name
        self.labelRank = labelRank
    }

    private enum CodingKeys: String, CodingKey {
        case labelX = "LABEL_X"
        case labelY = "LABEL_Y"
        case name = "NAME"
        case labelRank = "LABELRANK"
    }
}

public struct GeoJSONFeature: Decodable, Equatable, Sendable {
    public let properties: GeoJSONProperties
    public let geometry: GeoJSONGeometry?

    public init(properties: GeoJSONProperties, geometry: GeoJSONGeometry?) {
        self.properties = properties
        self.geometry = geometry
    }
}

public struct GeoJSONFeatureCollection: Decodable, Equatable, Sendable {
    public let features: [GeoJSONFeature]

    public init(features: [GeoJSONFeature]) {
        self.features = features
    }
}

public enum AeroRouteGeoJSONError: Error, Equatable, LocalizedError {
    case resourceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            "GeoJSON resource not found: \(name)"
        }
    }
}

public enum AeroRouteGeoJSON {
    public static func decodeFeatureCollection(from data: Data) throws -> GeoJSONFeatureCollection {
        try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
    }

    public static func loadBundledResource(named name: String) throws -> GeoJSONFeatureCollection {
        let resourceName = (name as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "geojson") else {
            throw AeroRouteGeoJSONError.resourceNotFound(name)
        }
        return try decodeFeatureCollection(from: Data(contentsOf: url))
    }
}
