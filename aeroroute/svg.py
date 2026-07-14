from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import timedelta
from importlib.resources import files
from pathlib import Path
from xml.etree import ElementTree as ET

from .geometry import (
    geojson_path,
    interpolating_bezier_path,
    map_viewport,
    project,
    unwrap_longitudes,
)
from .model import Track

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)


def _tag(name: str) -> str:
    return f"{{{SVG_NS}}}{name}"


@dataclass(frozen=True, slots=True)
class MapStyle:
    ocean: str = "#B2BAC3"
    land: str = "#D9D9D9"
    coastline: str = "#787C80"
    borders: str = "#A9ADB2"
    route: str = "#183143"
    marker: str = "#E05B45"
    text: str = "#171D21"
    route_width: float = 1.2
    coastline_width: float = 0.8
    border_width: float = 0.55
    font_family: str = "Helvetica Neue, Helvetica, Arial, sans-serif"


@dataclass(frozen=True, slots=True)
class RenderOptions:
    width: int = 1600
    height: int = 1000
    show_borders: bool = True
    show_country_labels: bool = False
    show_airports: bool = False
    show_flight_number: bool = False
    flight_number: str | None = None
    origin_code: str | None = None
    destination_code: str | None = None
    origin_name: str | None = None
    destination_name: str | None = None


@dataclass(frozen=True, slots=True)
class RenderStats:
    source_points: int
    curve_segments: int
    start_xy: tuple[float, float]
    end_xy: tuple[float, float]


def _load_geojson(name: str) -> dict:
    resource = files("aeroroute.data").joinpath(name)
    return json.loads(resource.read_text(encoding="utf-8"))


def _combined_map_path(features: list[dict], width: int, height: int) -> str:
    return " ".join(
        path
        for feature in features
        if (path := geojson_path(feature["geometry"], width, height))
    )


def _add_text(
    parent: ET.Element,
    text: str,
    x: float,
    y: float,
    *,
    fill: str,
    size: float,
    family: str,
    weight: str = "400",
    anchor: str = "start",
    letter_spacing: str | None = None,
    element_id: str | None = None,
) -> ET.Element:
    attributes = {
        "x": f"{x:.3f}",
        "y": f"{y:.3f}",
        "fill": fill,
        "font-size": str(size),
        "font-family": family,
        "font-weight": weight,
        "text-anchor": anchor,
    }
    if letter_spacing:
        attributes["letter-spacing"] = letter_spacing
    if element_id:
        attributes["id"] = element_id
    node = ET.SubElement(parent, _tag("text"), attributes)
    node.text = text
    return node


def _format_duration(track: Track) -> str:
    seconds = max(0.0, track.end.timestamp - track.start.timestamp)
    minutes = int(round(seconds / 60.0))
    hours, minutes = divmod(minutes, 60)
    return f"{hours}H {minutes:02d}M"


def _flight_number(track: Track, options: RenderOptions) -> str:
    if options.flight_number:
        return options.flight_number
    return track.source.stem.split("_", 1)[0]


def build_svg(
    track: Track,
    *,
    options: RenderOptions | None = None,
    style: MapStyle | None = None,
) -> tuple[str, RenderStats]:
    options = options or RenderOptions()
    style = style or MapStyle()
    width, height = options.width, options.height
    if width < 320 or height < 200:
        raise ValueError("canvas must be at least 320 x 200")

    root = ET.Element(
        _tag("svg"),
        {
            "viewBox": f"0 0 {width} {height}",
            "width": str(width),
            "height": str(height),
            "style": f"background-color:{style.ocean};background:{style.ocean}",
            "overflow": "hidden",
            "role": "img",
            "aria-labelledby": "map-title map-description",
            "data-source-points": str(len(track.points)),
        },
    )
    title = ET.SubElement(root, _tag("title"), {"id": "map-title"})
    title.text = f"{_flight_number(track, options)} flight track"
    description = ET.SubElement(root, _tag("desc"), {"id": "map-description"})
    description.text = (
        f"ADS-B track rendered from all {len(track.points)} source positions as an "
        "interpolating cubic Bezier path."
    )

    background_group = ET.SubElement(root, _tag("g"), {"id": "background"})
    ET.SubElement(
        background_group,
        _tag("rect"),
        {
            "id": "ocean",
            "x": "0",
            "y": "0",
            "width": str(width),
            "height": str(height),
            "fill": style.ocean,
        },
    )

    defs = ET.SubElement(root, _tag("defs"))
    left, top, right, bottom = map_viewport(width, height)
    clip_path = ET.SubElement(defs, _tag("clipPath"), {"id": "map-viewport"})
    ET.SubElement(
        clip_path,
        _tag("rect"),
        {
            "x": f"{left:.3f}",
            "y": f"{top:.3f}",
            "width": f"{right - left:.3f}",
            "height": f"{bottom - top:.3f}",
        },
    )

    map_group = ET.SubElement(
        root,
        _tag("g"),
        {"id": "map-layers", "clip-path": "url(#map-viewport)"},
    )

    land_data = _load_geojson("ne_110m_land.geojson")
    country_data = _load_geojson("ne_110m_admin_0_countries.geojson")
    land_path = _combined_map_path(land_data["features"], width, height)
    country_path = _combined_map_path(country_data["features"], width, height)

    ET.SubElement(
        map_group,
        _tag("path"),
        {"id": "land", "d": land_path, "fill": style.land, "fill-rule": "evenodd"},
    )
    if options.show_borders:
        ET.SubElement(
            map_group,
            _tag("path"),
            {
                "id": "country-borders",
                "d": country_path,
                "fill": "none",
                "stroke": style.borders,
                "stroke-width": str(style.border_width),
                "vector-effect": "non-scaling-stroke",
            },
        )
    ET.SubElement(
        map_group,
        _tag("path"),
        {
            "id": "coastline",
            "d": land_path,
            "fill": "none",
            "stroke": style.coastline,
            "stroke-width": str(style.coastline_width),
            "vector-effect": "non-scaling-stroke",
        },
    )

    if options.show_country_labels:
        labels = ET.SubElement(map_group, _tag("g"), {"id": "country-labels"})
        for feature in country_data["features"]:
            properties = feature.get("properties", {})
            lon = properties.get("LABEL_X")
            lat = properties.get("LABEL_Y")
            name = properties.get("NAME")
            rank = properties.get("LABELRANK", 99)
            if lon is None or lat is None or not name or rank > 5:
                continue
            x, y = project(float(lon), float(lat), width, height)
            _add_text(
                labels,
                str(name),
                x,
                y,
                fill=style.text,
                size=max(7.0, width / 190.0),
                family=style.font_family,
                anchor="middle",
            ).set("opacity", "0.58")

    unwrapped = unwrap_longitudes(
        (point.longitude, point.latitude) for point in track.points
    )
    projected_track = [project(lon, lat, width, height) for lon, lat in unwrapped]
    route_d, curve_segments = interpolating_bezier_path(projected_track)
    ET.SubElement(
        defs,
        _tag("path"),
        {
            "id": "flight-track-geometry",
            "d": route_d,
            "data-source-points": str(len(track.points)),
            "data-curve-segments": str(curve_segments),
        },
    )
    route_group = ET.SubElement(
        root,
        _tag("g"),
        {
            "id": "flight-track",
            "clip-path": "url(#map-viewport)",
            "fill": "none",
            "stroke": style.route,
            "stroke-width": str(style.route_width),
            "stroke-linecap": "round",
            "stroke-linejoin": "round",
            "vector-effect": "non-scaling-stroke",
        },
    )
    # Render concrete path elements instead of SVG <use>. Some otherwise valid
    # SVG rasterizers still omit href-based geometry. Only copies intersecting
    # the viewport are emitted, which also makes antimeridian tracks wrap.
    minimum_x = min(point[0] for point in projected_track)
    maximum_x = max(point[0] for point in projected_track)
    map_width = right - left
    for shift in (-2, -1, 0, 1, 2):
        offset = shift * map_width
        if maximum_x + offset < left or minimum_x + offset > right:
            continue
        attributes = {"d": route_d, "data-copy-shift": str(shift)}
        if shift:
            attributes["transform"] = f"translate({offset} 0)"
        ET.SubElement(route_group, _tag("path"), attributes)

    start_xy = project(track.start.longitude, track.start.latitude, width, height)
    end_xy = project(track.end.longitude, track.end.latitude, width, height)
    marker_group = ET.SubElement(root, _tag("g"), {"id": "endpoint-markers"})
    ET.SubElement(
        marker_group,
        _tag("circle"),
        {
            "id": "origin-marker",
            "cx": f"{start_xy[0]:.6f}",
            "cy": f"{start_xy[1]:.6f}",
            "r": "4.5",
            "fill": style.marker,
            "data-latitude": f"{track.start.latitude:.6f}",
            "data-longitude": f"{track.start.longitude:.6f}",
        },
    )
    ET.SubElement(
        marker_group,
        _tag("circle"),
        {
            "id": "destination-marker",
            "cx": f"{end_xy[0]:.6f}",
            "cy": f"{end_xy[1]:.6f}",
            "r": "4.5",
            "fill": style.marker,
            "data-latitude": f"{track.end.latitude:.6f}",
            "data-longitude": f"{track.end.longitude:.6f}",
        },
    )

    if options.show_airports:
        label_group = ET.SubElement(root, _tag("g"), {"id": "airport-labels"})
        origin_label = " · ".join(
            value for value in (options.origin_code, options.origin_name) if value
        ) or "ORIGIN"
        destination_label = " · ".join(
            value for value in (options.destination_code, options.destination_name) if value
        ) or "DESTINATION"
        _add_text(
            label_group,
            origin_label,
            start_xy[0] - 12,
            start_xy[1] + 5,
            fill=style.text,
            size=14,
            family=style.font_family,
            weight="600",
            anchor="end",
        )
        _add_text(
            label_group,
            destination_label,
            end_xy[0] + 13,
            end_xy[1] + 5,
            fill=style.text,
            size=14,
            family=style.font_family,
            weight="600",
        )

    if options.show_flight_number:
        metadata = ET.SubElement(root, _tag("g"), {"id": "flight-metadata"})
        left = max(32.0, width * 0.045)
        baseline = height - max(44.0, height * 0.06)
        title_size = max(34.0, min(58.0, width / 28.0))
        flight_number = _flight_number(track, options)
        if options.origin_name and options.destination_name:
            route_name = f"{options.origin_name.upper()} — {options.destination_name.upper()}"
        else:
            route_name = track.callsign or "FLIGHT TRACK"
        date = track.start.utc.strftime("%d %b %Y").upper()
        _add_text(
            metadata,
            flight_number,
            left,
            baseline - 76,
            fill=style.text,
            size=title_size,
            family=style.font_family,
            weight="600",
            letter_spacing="0.5",
        )
        _add_text(
            metadata,
            route_name,
            left,
            baseline - 35,
            fill=style.text,
            size=22,
            family=style.font_family,
            weight="500",
            letter_spacing="0.6",
        )
        ET.SubElement(
            metadata,
            _tag("line"),
            {
                "x1": f"{left:.3f}",
                "x2": f"{left + min(280.0, width * 0.2):.3f}",
                "y1": f"{baseline - 18:.3f}",
                "y2": f"{baseline - 18:.3f}",
                "stroke": style.marker,
                "stroke-width": "2",
            },
        )
        _add_text(
            metadata,
            f"{date} · {_format_duration(track)}",
            left,
            baseline + 8,
            fill=style.text,
            size=15,
            family=style.font_family,
            letter_spacing="0.4",
        ).set("opacity", "0.82")

    ET.indent(root, space="  ")
    svg = ET.tostring(root, encoding="unicode", xml_declaration=False)
    return svg + "\n", RenderStats(
        source_points=len(track.points),
        curve_segments=curve_segments,
        start_xy=start_xy,
        end_xy=end_xy,
    )


def write_svg(
    track: Track,
    destination: str | Path,
    *,
    options: RenderOptions | None = None,
    style: MapStyle | None = None,
) -> RenderStats:
    svg, stats = build_svg(track, options=options, style=style)
    output = Path(destination)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(svg, encoding="utf-8")
    return stats
