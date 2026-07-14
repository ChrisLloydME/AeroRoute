from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from math import asin, cos, radians, sin, sqrt
from pathlib import Path


class TrackDataError(ValueError):
    """Raised when an ADS-B row cannot be represented safely."""


@dataclass(frozen=True, slots=True)
class TrackPoint:
    timestamp: float
    utc: datetime
    callsign: str
    latitude: float
    longitude: float
    altitude: float | None
    speed: float | None
    direction: float | None


@dataclass(frozen=True, slots=True)
class Track:
    source: Path
    points: tuple[TrackPoint, ...]
    waypoint_indices: tuple[int, ...] = ()

    @property
    def callsign(self) -> str:
        return next((point.callsign for point in self.points if point.callsign), "")

    @property
    def start(self) -> TrackPoint:
        return self.points[0]

    @property
    def end(self) -> TrackPoint:
        return self.points[-1]

    @property
    def waypoints(self) -> tuple[TrackPoint, ...]:
        indices = self.waypoint_indices or (0, len(self.points) - 1)
        return tuple(self.points[index] for index in indices)


def load_track(path: str | Path) -> Track:
    """Load every CSV row, validate it, and return points sorted by timestamp.

    No sampling, deduplication, or coordinate smoothing is performed. Repeated
    coordinates remain repeated curve nodes in the generated SVG.
    """

    from .fr24 import load_fr24

    return load_fr24(path).track


def endpoint_distance_km(first: Track, second: Track) -> float:
    """Great-circle distance from the first leg's end to the second leg's start."""

    lat1, lon1 = radians(first.end.latitude), radians(first.end.longitude)
    lat2, lon2 = radians(second.start.latitude), radians(second.start.longitude)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    value = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 6371.0088 * 2 * asin(sqrt(value))


def validate_leg_order(
    tracks: list[Track] | tuple[Track, ...], *, tolerance_km: float = 50.0
) -> tuple[float, ...]:
    """Validate ordered end-to-start connections and return their distances."""

    if tolerance_km <= 0:
        raise ValueError("continuity tolerance must be greater than zero")
    distances = tuple(endpoint_distance_km(a, b) for a, b in zip(tracks, tracks[1:]))
    for index, distance in enumerate(distances, start=1):
        if distance > tolerance_km:
            raise TrackDataError(
                f"leg {index} does not connect to leg {index + 1}: "
                f"end-to-start distance is {distance:.1f} km"
            )
    return distances


def combine_tracks(
    paths: list[str | Path] | tuple[str | Path, ...],
    *,
    source_name: str = "itinerary",
    validate_continuity: bool = False,
    tolerance_km: float = 50.0,
) -> Track:
    """Combine ordered flight legs without re-sorting across leg boundaries."""

    if not paths:
        raise TrackDataError("at least one ADS-B CSV file is required")
    legs = [load_track(path) for path in paths]
    if validate_continuity:
        validate_leg_order(legs, tolerance_km=tolerance_km)
    points: list[TrackPoint] = []
    waypoint_indices = [0]
    for leg in legs:
        points.extend(leg.points)
        waypoint_indices.append(len(points) - 1)
    return Track(
        source=Path(source_name),
        points=tuple(points),
        waypoint_indices=tuple(waypoint_indices),
    )
