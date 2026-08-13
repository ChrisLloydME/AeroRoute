import Foundation

public struct MapStyle: Equatable, Sendable {
    public var ocean: String
    public var land: String
    public var coastline: String
    public var borders: String
    public var route: String
    public var marker: String
    public var text: String
    public var routeWidth: Double
    public var coastlineWidth: Double
    public var borderWidth: Double
    public var fontFamily: String

    public init(
        ocean: String = "#B2BAC3",
        land: String = "#D9D9D9",
        coastline: String = "#787C80",
        borders: String = "#A9ADB2",
        route: String = "#183143",
        marker: String = "#E05B45",
        text: String = "#171D21",
        routeWidth: Double = 1.2,
        coastlineWidth: Double = 0.8,
        borderWidth: Double = 0.55,
        fontFamily: String = "Helvetica Neue, Helvetica, Arial, sans-serif"
    ) {
        self.ocean = ocean
        self.land = land
        self.coastline = coastline
        self.borders = borders
        self.route = route
        self.marker = marker
        self.text = text
        self.routeWidth = routeWidth
        self.coastlineWidth = coastlineWidth
        self.borderWidth = borderWidth
        self.fontFamily = fontFamily
    }
}

public struct RenderOptions: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var scale: Double
    public var showBorders: Bool
    public var showCountryLabels: Bool
    public var showAirports: Bool
    public var showFlightNumber: Bool
    public var fitMapToRoute: Bool
    public var centerRouteOnWorldMap: Bool
    public var flightNumber: String?
    public var originCode: String?
    public var destinationCode: String?
    public var originName: String?
    public var destinationName: String?
    public var waypointCodes: [String]
    public var waypointNames: [String]
    public var routeName: String?
    public var metadataDetail: String?

    public init(
        width: Int = 1600,
        height: Int = 1000,
        scale: Double = 1,
        showBorders: Bool = true,
        showCountryLabels: Bool = false,
        showAirports: Bool = false,
        showFlightNumber: Bool = false,
        fitMapToRoute: Bool = false,
        centerRouteOnWorldMap: Bool = false,
        flightNumber: String? = nil,
        originCode: String? = nil,
        destinationCode: String? = nil,
        originName: String? = nil,
        destinationName: String? = nil,
        waypointCodes: [String] = [],
        waypointNames: [String] = [],
        routeName: String? = nil,
        metadataDetail: String? = nil
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        self.showBorders = showBorders
        self.showCountryLabels = showCountryLabels
        self.showAirports = showAirports
        self.showFlightNumber = showFlightNumber
        self.fitMapToRoute = fitMapToRoute
        self.centerRouteOnWorldMap = centerRouteOnWorldMap
        self.flightNumber = flightNumber
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.originName = originName
        self.destinationName = destinationName
        self.waypointCodes = waypointCodes
        self.waypointNames = waypointNames
        self.routeName = routeName
        self.metadataDetail = metadataDetail
    }
}

public struct RenderStats: Equatable, Sendable {
    public let sourcePoints: Int
    public let curveSegments: Int
    public let startXY: Point2D
    public let endXY: Point2D

    public init(
        sourcePoints: Int,
        curveSegments: Int,
        startXY: Point2D,
        endXY: Point2D
    ) {
        self.sourcePoints = sourcePoints
        self.curveSegments = curveSegments
        self.startXY = startXY
        self.endXY = endXY
    }
}

public enum SVGRendererError: Error, Equatable, LocalizedError {
    case invalidCanvas
    case invalidScale
    case insufficientPoints

    public var errorDescription: String? {
        switch self {
        case .invalidCanvas:
            "canvas must be at least 320 x 200"
        case .invalidScale:
            "scale must be greater than zero"
        case .insufficientPoints:
            "at least two points are required"
        }
    }
}

public enum SVGRenderer {
    private static let svgNamespace = "http://www.w3.org/2000/svg"
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func buildSVG(
        track: Track,
        options: RenderOptions = RenderOptions(),
        style: MapStyle = MapStyle()
    ) throws -> (svg: String, stats: RenderStats) {
        guard options.width >= 320, options.height >= 200 else {
            throw SVGRendererError.invalidCanvas
        }
        guard options.scale > 0 else {
            throw SVGRendererError.invalidScale
        }
        guard track.points.count >= 2 else {
            throw SVGRendererError.insufficientPoints
        }

        let width = options.width
        let height = options.height
        let widthDouble = Double(width)
        let heightDouble = Double(height)
        let outputWidth = Int(
            (widthDouble * options.scale).rounded(.toNearestOrEven)
        )
        let outputHeight = Int(
            (heightDouble * options.scale).rounded(.toNearestOrEven)
        )

        let root = OrderedXMLNode(
            "svg",
            attributes: [
                ("xmlns", svgNamespace),
                ("viewBox", "0 0 \(width) \(height)"),
                ("width", String(outputWidth)),
                ("height", String(outputHeight)),
                ("style", "background-color:\(style.ocean);background:\(style.ocean)"),
                ("overflow", "hidden"),
                ("role", "img"),
                ("aria-labelledby", "map-title map-description"),
                ("data-source-points", String(track.points.count)),
            ]
        )

        let displayedFlightNumber = flightNumber(track: track, options: options)
        root.add(
            "title",
            attributes: [("id", "map-title")],
            text: "\(displayedFlightNumber) flight track"
        )
        root.add(
            "desc",
            attributes: [("id", "map-description")],
            text: "ADS-B track rendered from all \(track.points.count) source positions as an interpolating cubic Bezier path."
        )

        let background = root.add("g", attributes: [("id", "background")])
        background.add(
            "rect",
            attributes: [
                ("id", "ocean"),
                ("x", "0"),
                ("y", "0"),
                ("width", String(width)),
                ("height", String(height)),
                ("fill", style.ocean),
            ]
        )

        let definitions = root.add("defs")
        let viewport = options.fitMapToRoute
            ? MapViewport(left: 0, top: 0, right: widthDouble, bottom: heightDouble)
            : AeroRouteGeometry.mapViewport(width: widthDouble, height: heightDouble)
        let unwrapped = AeroRouteGeometry.unwrapLongitudes(
            track.points.map { ($0.longitude, $0.latitude) }
        )
        let projection: MapProjection?
        if options.fitMapToRoute {
            projection = AeroRouteGeometry.routeFittingProjection(
                coordinates: unwrapped,
                width: widthDouble,
                height: heightDouble,
                viewport: viewport
            )
        } else if options.centerRouteOnWorldMap {
            projection = AeroRouteGeometry.routeCenteredWorldProjection(
                coordinates: unwrapped
            )
        } else {
            projection = nil
        }
        if options.fitMapToRoute {
            root.setAttribute("data-map-scope", "route")
        } else if let projection {
            root.setAttribute("data-map-scope", "world-route-centered")
            root.setAttribute(
                "data-map-center-longitude",
                fixed(projection.centerLongitude, digits: 6)
            )
        }
        let clipPath = definitions.add(
            "clipPath",
            attributes: [("id", "map-viewport")]
        )
        clipPath.add(
            "rect",
            attributes: [
                ("x", fixed(viewport.left, digits: 3)),
                ("y", fixed(viewport.top, digits: 3)),
                ("width", fixed(viewport.right - viewport.left, digits: 3)),
                ("height", fixed(viewport.bottom - viewport.top, digits: 3)),
            ]
        )

        let mapLayers = root.add(
            "g",
            attributes: [
                ("id", "map-layers"),
                ("clip-path", "url(#map-viewport)"),
            ]
        )
        let land = try AeroRouteGeoJSON.loadBundledResource(
            named: "ne_110m_land.geojson"
        )
        let countries = try AeroRouteGeoJSON.loadBundledResource(
            named: "ne_110m_admin_0_countries.geojson"
        )
        let landPath = combinedMapPath(
            features: land.features,
            width: widthDouble,
            height: heightDouble,
            projection: projection,
            viewport: viewport,
            includeAdjacentWorldCopies: options.centerRouteOnWorldMap
        )
        let countryPath = combinedMapPath(
            features: countries.features,
            width: widthDouble,
            height: heightDouble,
            projection: projection,
            viewport: viewport,
            includeAdjacentWorldCopies: options.centerRouteOnWorldMap
        )

        mapLayers.add(
            "path",
            attributes: [
                ("id", "land"),
                ("d", landPath),
                ("fill", style.land),
                ("fill-rule", "evenodd"),
            ]
        )
        if options.showBorders {
            mapLayers.add(
                "path",
                attributes: [
                    ("id", "country-borders"),
                    ("d", countryPath),
                    ("fill", "none"),
                    ("stroke", style.borders),
                    ("stroke-width", pythonFloat(style.borderWidth)),
                ]
            )
        }
        mapLayers.add(
            "path",
            attributes: [
                ("id", "coastline"),
                ("d", landPath),
                ("fill", "none"),
                ("stroke", style.coastline),
                ("stroke-width", pythonFloat(style.coastlineWidth)),
            ]
        )

        if options.showCountryLabels {
            let labels = mapLayers.add(
                "g",
                attributes: [("id", "country-labels")]
            )
            for feature in countries.features {
                let properties = feature.properties
                guard
                    let longitude = properties.labelX,
                    let latitude = properties.labelY,
                    let name = properties.name,
                    !name.isEmpty,
                    (properties.labelRank ?? 99) <= 5
                else {
                    continue
                }
                let point = project(
                    longitude: longitude,
                    latitude: latitude,
                    width: widthDouble,
                    height: heightDouble,
                    projection: projection,
                    viewport: viewport
                )
                let label = addText(
                    to: labels,
                    text: name,
                    x: point.x,
                    y: point.y,
                    fill: style.text,
                    size: pythonFloat(max(7, widthDouble / 190)),
                    family: style.fontFamily,
                    anchor: "middle"
                )
                label.setAttribute("opacity", "0.58")
            }
        }

        let projectedTrack = unwrapped.map {
            project(
                longitude: $0.longitude,
                latitude: $0.latitude,
                width: widthDouble,
                height: heightDouble,
                projection: projection,
                viewport: viewport,
                normalizeLongitude: false
            )
        }
        let route = AeroRouteGeometry.interpolatingBezierPath(projectedTrack)
        definitions.add(
            "path",
            attributes: [
                ("id", "flight-track-geometry"),
                ("d", route.path),
                ("data-source-points", String(track.points.count)),
                ("data-curve-segments", String(route.segments)),
            ]
        )

        let routeGroup = root.add(
            "g",
            attributes: [
                ("id", "flight-track"),
                ("clip-path", "url(#map-viewport)"),
                ("fill", "none"),
                ("stroke", style.route),
                ("stroke-width", pythonFloat(style.routeWidth)),
                ("stroke-linecap", "round"),
                ("stroke-linejoin", "round"),
            ]
        )
        let minimumX = projectedTrack.map(\.x).min()!
        let maximumX = projectedTrack.map(\.x).max()!
        let mapWidth = projection.map {
            360 / ($0.maximumLongitude - $0.minimumLongitude)
                * (viewport.right - viewport.left)
        } ?? (viewport.right - viewport.left)
        for shift in -2...2 {
            let offset = Double(shift) * mapWidth
            if maximumX + offset < viewport.left
                || minimumX + offset > viewport.right
            {
                continue
            }
            var attributes = [
                ("d", route.path),
                ("data-copy-shift", String(shift)),
            ]
            if shift != 0 {
                attributes.append(("transform", "translate(\(pythonFloat(offset)) 0)"))
            }
            routeGroup.add("path", attributes: attributes)
        }

        let startXY = project(
            longitude: track.start.longitude,
            latitude: track.start.latitude,
            width: widthDouble,
            height: heightDouble,
            projection: projection,
            viewport: viewport
        )
        let endXY = project(
            longitude: track.end.longitude,
            latitude: track.end.latitude,
            width: widthDouble,
            height: heightDouble,
            projection: projection,
            viewport: viewport
        )
        let markerGroup = root.add(
            "g",
            attributes: [("id", "endpoint-markers")]
        )
        let waypoints = track.waypoints
        for (index, waypoint) in waypoints.enumerated() {
            let point = project(
                longitude: waypoint.longitude,
                latitude: waypoint.latitude,
                width: widthDouble,
                height: heightDouble,
                projection: projection,
                viewport: viewport
            )
            let markerID: String
            if index == 0 {
                markerID = "origin-marker"
            } else if index == waypoints.count - 1 {
                markerID = "destination-marker"
            } else {
                markerID = "waypoint-marker-\(index)"
            }
            markerGroup.add(
                "circle",
                attributes: [
                    ("id", markerID),
                    ("cx", fixed(point.x, digits: 6)),
                    ("cy", fixed(point.y, digits: 6)),
                    ("r", "4.5"),
                    ("fill", style.marker),
                    ("data-latitude", fixed(waypoint.latitude, digits: 6)),
                    ("data-longitude", fixed(waypoint.longitude, digits: 6)),
                ]
            )
        }

        if options.showAirports {
            addAirportLabels(
                to: root,
                waypoints: waypoints,
                options: options,
                style: style,
                width: widthDouble,
                height: heightDouble,
                projection: projection,
                viewport: viewport
            )
        }

        if options.showFlightNumber {
            addMetadata(
                to: root,
                track: track,
                options: options,
                style: style,
                flightNumber: displayedFlightNumber,
                width: widthDouble,
                height: heightDouble
            )
        }

        let svg = root.serialized() + "\n"
        return (
            svg,
            RenderStats(
                sourcePoints: track.points.count,
                curveSegments: route.segments,
                startXY: startXY,
                endXY: endXY
            )
        )
    }

    @discardableResult
    public static func writeSVG(
        track: Track,
        destination: URL,
        options: RenderOptions = RenderOptions(),
        style: MapStyle = MapStyle()
    ) throws -> RenderStats {
        let rendered = try buildSVG(track: track, options: options, style: style)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(rendered.svg.utf8).write(to: destination)
        return rendered.stats
    }

    private static func combinedMapPath(
        features: [GeoJSONFeature],
        width: Double,
        height: Double,
        projection: MapProjection?,
        viewport: MapViewport,
        includeAdjacentWorldCopies: Bool
    ) -> String {
        features.compactMap { feature in
            guard let geometry = feature.geometry else { return nil }
            let path: String
            if let projection {
                path = AeroRouteGeometry.geoJSONPath(
                    geometry: geometry,
                    width: width,
                    height: height,
                    projection: projection,
                    viewport: viewport,
                    includeAdjacentWorldCopies: includeAdjacentWorldCopies
                )
            } else {
                path = AeroRouteGeometry.geoJSONPath(
                    geometry: geometry,
                    width: width,
                    height: height
                )
            }
            return path.isEmpty ? nil : path
        }.joined(separator: " ")
    }

    private static func addAirportLabels(
        to root: OrderedXMLNode,
        waypoints: [TrackPoint],
        options: RenderOptions,
        style: MapStyle,
        width: Double,
        height: Double,
        projection: MapProjection?,
        viewport: MapViewport
    ) {
        let labels = root.add("g", attributes: [("id", "airport-labels")])
        let codes = options.waypointCodes.isEmpty
            ? [options.originCode ?? "", options.destinationCode ?? ""]
            : options.waypointCodes
        let names = options.waypointNames.isEmpty
            ? [options.originName ?? "", options.destinationName ?? ""]
            : options.waypointNames

        for (index, waypoint) in waypoints.enumerated() {
            let code = index < codes.count ? codes[index] : ""
            let name = index < names.count ? names[index] : ""
            let pieces = [code, name].filter { !$0.isEmpty }
            let label = pieces.isEmpty
                ? "STOP \(index + 1)"
                : pieces.joined(separator: " · ")
            let point = project(
                longitude: waypoint.longitude,
                latitude: waypoint.latitude,
                width: width,
                height: height,
                projection: projection,
                viewport: viewport
            )
            let isFirst = index == 0
            addText(
                to: labels,
                text: label,
                x: point.x + (isFirst ? -12 : 12),
                y: point.y + 5,
                fill: style.text,
                size: "14",
                family: style.fontFamily,
                weight: "600",
                anchor: isFirst ? "end" : "start"
            )
        }
    }

    private static func project(
        longitude: Double,
        latitude: Double,
        width: Double,
        height: Double,
        projection: MapProjection?,
        viewport: MapViewport,
        normalizeLongitude: Bool = true
    ) -> Point2D {
        guard let projection else {
            return AeroRouteGeometry.project(
                longitude: longitude,
                latitude: latitude,
                width: width,
                height: height
            )
        }
        let projectedLongitude = normalizeLongitude
            ? AeroRouteGeometry.longitudeNearestProjectionCenter(
                longitude,
                projection: projection
            )
            : longitude
        return AeroRouteGeometry.project(
            longitude: projectedLongitude,
            latitude: latitude,
            width: width,
            height: height,
            projection: projection,
            viewport: viewport
        )
    }

    private static func addMetadata(
        to root: OrderedXMLNode,
        track: Track,
        options: RenderOptions,
        style: MapStyle,
        flightNumber: String,
        width: Double,
        height: Double
    ) {
        let metadata = root.add(
            "g",
            attributes: [("id", "flight-metadata")]
        )
        let left = max(32, width * 0.045)
        let baseline = height - max(44, height * 0.06)
        let titleSize = max(34, min(58, width / 28))

        let displayedRouteName: String
        if let routeName = nonempty(options.routeName) {
            displayedRouteName = routeName
        } else if !options.waypointNames.isEmpty {
            displayedRouteName = options.waypointNames
                .map { $0.uppercased() }
                .joined(separator: " — ")
        } else if
            let origin = nonempty(options.originName),
            let destination = nonempty(options.destinationName)
        {
            displayedRouteName = "\(origin.uppercased()) — \(destination.uppercased())"
        } else {
            displayedRouteName = track.callsign.isEmpty ? "FLIGHT TRACK" : track.callsign
        }

        addText(
            to: metadata,
            text: flightNumber,
            x: left,
            y: baseline - 76,
            fill: style.text,
            size: pythonFloat(titleSize),
            family: style.fontFamily,
            weight: "600",
            letterSpacing: "0.5"
        )
        addText(
            to: metadata,
            text: displayedRouteName,
            x: left,
            y: baseline - 35,
            fill: style.text,
            size: "22",
            family: style.fontFamily,
            weight: "500",
            letterSpacing: "0.6"
        )
        metadata.add(
            "line",
            attributes: [
                ("x1", fixed(left, digits: 3)),
                ("x2", fixed(left + min(280, width * 0.2), digits: 3)),
                ("y1", fixed(baseline - 18, digits: 3)),
                ("y2", fixed(baseline - 18, digits: 3)),
                ("stroke", style.marker),
                ("stroke-width", "2"),
            ]
        )

        let detail = nonempty(options.metadataDetail)
            ?? "\(formattedDate(track.start.utc)) · \(formattedDuration(track: track))"
        let detailNode = addText(
            to: metadata,
            text: detail,
            x: left,
            y: baseline + 8,
            fill: style.text,
            size: "15",
            family: style.fontFamily,
            letterSpacing: "0.4"
        )
        detailNode.setAttribute("opacity", "0.82")
    }

    @discardableResult
    private static func addText(
        to parent: OrderedXMLNode,
        text: String,
        x: Double,
        y: Double,
        fill: String,
        size: String,
        family: String,
        weight: String = "400",
        anchor: String = "start",
        letterSpacing: String? = nil,
        elementID: String? = nil
    ) -> OrderedXMLNode {
        var attributes = [
            ("x", fixed(x, digits: 3)),
            ("y", fixed(y, digits: 3)),
            ("fill", fill),
            ("font-size", size),
            ("font-family", family),
            ("font-weight", weight),
            ("text-anchor", anchor),
        ]
        if let letterSpacing {
            attributes.append(("letter-spacing", letterSpacing))
        }
        if let elementID {
            attributes.append(("id", elementID))
        }
        return parent.add("text", attributes: attributes, text: text)
    }

    private static func flightNumber(track: Track, options: RenderOptions) -> String {
        if let value = nonempty(options.flightNumber) {
            return value
        }
        let stem = track.source.deletingPathExtension().lastPathComponent
        return String(stem.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    private static func formattedDuration(track: Track) -> String {
        let seconds = max(0, track.end.timestamp - track.start.timestamp)
        let totalMinutes = Int((seconds / 60).rounded(.toNearestOrEven))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%dH %02dM", locale: posixLocale, hours, minutes)
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    private static func fixed(_ value: Double, digits: Int) -> String {
        String(
            format: "%." + String(digits) + "f",
            locale: posixLocale,
            value
        )
    }

    private static func pythonFloat(_ value: Double) -> String {
        String(value)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
