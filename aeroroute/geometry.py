from __future__ import annotations

from math import hypot, sqrt
from typing import Iterable, Sequence

Point2D = tuple[float, float]


def map_viewport(width: float, height: float) -> tuple[float, float, float, float]:
    """Return the flat-map drawing bounds: left, top, right, bottom.

    The full longitude range is pinned to the canvas edges so routes crossing
    the antimeridian wrap exactly at the left and right boundaries. Antarctica
    remains outside the visible latitude range, leaving useful ocean space for
    the editorial metadata block.
    """

    return 0.0, height * 0.19, width, height * 0.82


def project(longitude: float, latitude: float, width: float, height: float) -> Point2D:
    """Project WGS84 coordinates to a strictly flat equirectangular map.

    Longitude affects only x and latitude affects only y. There is no Mercator
    scale, great-circle bowing, or latitude-dependent horizontal correction.
    """

    left, top, right, bottom = map_viewport(width, height)
    x = left + (longitude + 180.0) / 360.0 * (right - left)
    latitude_max = 85.0
    latitude_min = -60.0
    y = top + (latitude_max - latitude) / (latitude_max - latitude_min) * (bottom - top)
    return x, y


def unwrap_longitudes(coordinates: Iterable[tuple[float, float]]) -> list[tuple[float, float]]:
    """Keep adjacent longitudes continuous across the antimeridian."""

    unwrapped: list[tuple[float, float]] = []
    previous: float | None = None
    for longitude, latitude in coordinates:
        candidate = longitude
        if previous is not None:
            while candidate - previous > 180.0:
                candidate -= 360.0
            while candidate - previous < -180.0:
                candidate += 360.0
        unwrapped.append((candidate, latitude))
        previous = candidate
    return unwrapped


def _fmt(value: float) -> str:
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return "0" if text in {"-0", ""} else text


def interpolating_bezier_path(points: Sequence[Point2D]) -> tuple[str, int]:
    """Return a C1-continuous cubic path that passes through every input point.

    Chord-length knots use alpha=0.5 (centripetal parameterization). Each pair
    of adjacent source points becomes exactly one cubic Bezier segment, so the
    SVG contains all source points without drawing waypoint dots.
    """

    if len(points) < 2:
        raise ValueError("at least two points are required")

    knots = [0.0]
    for current, following in zip(points, points[1:]):
        distance = hypot(following[0] - current[0], following[1] - current[1])
        knots.append(knots[-1] + max(sqrt(distance), 1e-6))

    tangents: list[Point2D] = []
    for index, point in enumerate(points):
        if index == 0:
            delta = knots[1] - knots[0]
            tangent = (
                (points[1][0] - point[0]) / delta,
                (points[1][1] - point[1]) / delta,
            )
        elif index == len(points) - 1:
            delta = knots[-1] - knots[-2]
            tangent = (
                (point[0] - points[-2][0]) / delta,
                (point[1] - points[-2][1]) / delta,
            )
        else:
            delta = knots[index + 1] - knots[index - 1]
            tangent = (
                (points[index + 1][0] - points[index - 1][0]) / delta,
                (points[index + 1][1] - points[index - 1][1]) / delta,
            )
        tangents.append(tangent)

    commands = [f"M {_fmt(points[0][0])} {_fmt(points[0][1])}"]
    for index in range(len(points) - 1):
        start = points[index]
        end = points[index + 1]
        interval = knots[index + 1] - knots[index]
        control_1 = (
            start[0] + tangents[index][0] * interval / 3.0,
            start[1] + tangents[index][1] * interval / 3.0,
        )
        control_2 = (
            end[0] - tangents[index + 1][0] * interval / 3.0,
            end[1] - tangents[index + 1][1] * interval / 3.0,
        )
        commands.append(
            "C "
            f"{_fmt(control_1[0])} {_fmt(control_1[1])} "
            f"{_fmt(control_2[0])} {_fmt(control_2[1])} "
            f"{_fmt(end[0])} {_fmt(end[1])}"
        )
    return " ".join(commands), len(points) - 1


def geojson_path(geometry: dict, width: float, height: float) -> str:
    """Convert a GeoJSON Polygon or MultiPolygon into SVG path commands."""

    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])
    if geometry_type == "Polygon":
        polygons = [coordinates]
    elif geometry_type == "MultiPolygon":
        polygons = coordinates
    else:
        return ""

    commands: list[str] = []
    for polygon in polygons:
        for ring in polygon:
            if not ring:
                continue
            projected = [project(lon, lat, width, height) for lon, lat in ring]
            commands.append(f"M {_fmt(projected[0][0])} {_fmt(projected[0][1])}")
            commands.extend(f"L {_fmt(x)} {_fmt(y)}" for x, y in projected[1:])
            commands.append("Z")
    return " ".join(commands)
