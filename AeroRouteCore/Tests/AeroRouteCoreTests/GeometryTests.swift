import CryptoKit
import Foundation
import Testing
@testable import AeroRouteCore

struct GeometryTests {
    @Test func mapViewportAndProjectionMatchReference() {
        #expect(
            AeroRouteGeometry.mapViewport(width: 1_000, height: 1_000)
                == MapViewport(left: 0, top: 190, right: 1_000, bottom: 820)
        )
        #expect(
            AeroRouteGeometry.project(
                longitude: 0,
                latitude: 85,
                width: 1_000,
                height: 1_000
            ) == Point2D(x: 500, y: 190)
        )
        #expect(
            AeroRouteGeometry.project(
                longitude: 0,
                latitude: -60,
                width: 1_000,
                height: 1_000
            ) == Point2D(x: 500, y: 820)
        )
        #expect(
            AeroRouteGeometry.project(
                longitude: -180,
                latitude: 0,
                width: 1_000,
                height: 1_000
            ).x == 0
        )
        #expect(
            AeroRouteGeometry.project(
                longitude: 180,
                latitude: 0,
                width: 1_000,
                height: 1_000
            ).x == 1_000
        )
    }

    @Test func antimeridianLongitudesStayContinuous() {
        let coordinates: [(longitude: Double, latitude: Double)] = [
            (170, 1),
            (-175, 2),
            (-160, 3),
            (175, 4),
        ]

        let result = AeroRouteGeometry.unwrapLongitudes(coordinates)

        #expect(result.map { $0.longitude } == [170, 185, 200, 175])
        #expect(result.map { $0.latitude } == [1, 2, 3, 4])
    }

    @Test func routeFittingProjectionFitsTrackAndCanvasAspect() {
        let projection = AeroRouteGeometry.routeFittingProjection(
            coordinates: [
                (longitude: 8, latitude: 47),
                (longitude: 12, latitude: 49),
            ],
            width: 1_600,
            height: 1_000
        )
        let viewport = AeroRouteGeometry.mapViewport(width: 1_600, height: 1_000)
        let geographicAspect = (projection.maximumLongitude - projection.minimumLongitude)
            / (projection.maximumLatitude - projection.minimumLatitude)

        #expect(projection.minimumLongitude < 8)
        #expect(projection.maximumLongitude > 12)
        #expect(projection.minimumLatitude < 47)
        #expect(projection.maximumLatitude > 49)
        #expect(
            abs(geographicAspect - (viewport.right - viewport.left)
                / (viewport.bottom - viewport.top)) < 0.000_001
        )
    }

    @Test func routeFittingProjectionUsesShortAntimeridianSpan() {
        let projection = AeroRouteGeometry.routeFittingProjection(
            coordinates: [
                (longitude: 175, latitude: 10),
                (longitude: -175, latitude: 12),
            ],
            width: 1_600,
            height: 1_000
        )

        #expect(projection.centerLongitude == 180)
        #expect(projection.maximumLongitude - projection.minimumLongitude < 30)
        #expect(
            AeroRouteGeometry.longitudeNearestProjectionCenter(
                -175,
                projection: projection
            ) == 185
        )
    }

    @Test func coordinateFormattingMatchesPython() {
        #expect(AeroRouteGeometry.formatCoordinate(12.340000) == "12.34")
        #expect(AeroRouteGeometry.formatCoordinate(-0.0000001) == "0")
        #expect(AeroRouteGeometry.formatCoordinate(1.0 / 3.0) == "0.333333")
    }

    @Test func bezierPathUsesOneCubicPerSourceInterval() {
        let result = AeroRouteGeometry.interpolatingBezierPath([
            Point2D(x: 0, y: 0),
            Point2D(x: 3, y: 0),
            Point2D(x: 3, y: 4),
        ])

        #expect(result.segments == 2)
        #expect(
            result.path
                == "M 0 0 C 1 0 2.535898 -0.618802 3 0 "
                + "C 3.535898 0.714531 3 2.666667 3 4"
        )
    }

    @Test func repeatedPointsRemainInBezierPath() {
        let result = AeroRouteGeometry.interpolatingBezierPath([
            Point2D(x: 1, y: 1),
            Point2D(x: 1, y: 1),
            Point2D(x: 2, y: 2),
        ])

        #expect(result.segments == 2)
        #expect(
            result.path
                == "M 1 1 C 1 1 1 1 1 1 "
                + "C 1.333333 1.333333 1.666667 1.666667 2 2"
        )
    }

    @Test func polygonAndMultiPolygonKeepRingOrder() {
        let first: GeoJSONPolygonCoordinates = [[
            GeoJSONPosition(longitude: 0, latitude: 85),
            GeoJSONPosition(longitude: 180, latitude: -60),
            GeoJSONPosition(longitude: -180, latitude: -60),
            GeoJSONPosition(longitude: 0, latitude: 85),
        ]]
        let second: GeoJSONPolygonCoordinates = [[
            GeoJSONPosition(longitude: -180, latitude: 85),
            GeoJSONPosition(longitude: 0, latitude: -60),
        ]]

        #expect(
            AeroRouteGeometry.geoJSONPath(
                geometry: .polygon(first),
                width: 100,
                height: 100
            ) == "M 50 19 L 100 82 L 0 82 L 50 19 Z"
        )
        #expect(
            AeroRouteGeometry.geoJSONPath(
                geometry: .multiPolygon([first, second]),
                width: 100,
                height: 100
            ) == "M 50 19 L 100 82 L 0 82 L 50 19 Z M 0 19 L 50 82 Z"
        )
    }

    @Test func bundledGeoJSONResourcesDecodeInSourceOrder() throws {
        let land = try AeroRouteGeoJSON.loadBundledResource(named: "ne_110m_land.geojson")
        let countries = try AeroRouteGeoJSON.loadBundledResource(
            named: "ne_110m_admin_0_countries.geojson"
        )

        #expect(land.features.count == 127)
        #expect(countries.features.count == 177)
        #expect(land.features.first?.geometry != nil)
        #expect(countries.features.first?.properties.name == "Fiji")
        #expect(countries.features.first?.properties.labelX != nil)
    }

    @Test func bundledMapGeometryMatchesPythonReferenceBytes() throws {
        let expectations = [
            (
                name: "ne_110m_land.geojson",
                count: 123_819,
                sha256: "65a37b8a6a46f03278b80d73bb7d475527a42579544b2a2af38bc0fba961a7ae"
            ),
            (
                name: "ne_110m_admin_0_countries.geojson",
                count: 256_137,
                sha256: "2d990413aa7676c0b02480bd245e3c740df1f94c4e9a3a703485abee9db84164"
            ),
        ]

        for expectation in expectations {
            let collection = try AeroRouteGeoJSON.loadBundledResource(named: expectation.name)
            let path = collection.features.compactMap(\.geometry).map {
                AeroRouteGeometry.geoJSONPath(geometry: $0, width: 1_600, height: 1_000)
            }.filter { !$0.isEmpty }.joined(separator: " ")
            let digest = SHA256.hash(data: Data(path.utf8)).map {
                String(format: "%02x", $0)
            }.joined()

            #expect(path.utf8.count == expectation.count)
            #expect(digest == expectation.sha256)
        }
    }
}
