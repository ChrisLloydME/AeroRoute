from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime, timezone
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

    @property
    def callsign(self) -> str:
        return next((point.callsign for point in self.points if point.callsign), "")

    @property
    def start(self) -> TrackPoint:
        return self.points[0]

    @property
    def end(self) -> TrackPoint:
        return self.points[-1]


def _optional_float(value: str | None, *, row_number: int, field: str) -> float | None:
    if value is None or not value.strip():
        return None
    try:
        return float(value)
    except ValueError as exc:
        raise TrackDataError(f"row {row_number}: invalid {field}: {value!r}") from exc


def _parse_utc(value: str | None, timestamp: float, *, row_number: int) -> datetime:
    if value and value.strip():
        try:
            return datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError as exc:
            raise TrackDataError(f"row {row_number}: invalid UTC: {value!r}") from exc
    return datetime.fromtimestamp(timestamp, tz=timezone.utc)


def load_track(path: str | Path) -> Track:
    """Load every CSV row, validate it, and return points sorted by timestamp.

    No sampling, deduplication, or coordinate smoothing is performed. Repeated
    coordinates remain repeated curve nodes in the generated SVG.
    """

    source = Path(path)
    points: list[TrackPoint] = []
    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"Timestamp", "UTC", "Callsign", "Position"}
        missing = required.difference(reader.fieldnames or ())
        if missing:
            raise TrackDataError(f"missing CSV columns: {', '.join(sorted(missing))}")

        for row_number, row in enumerate(reader, start=2):
            try:
                timestamp = float(row["Timestamp"])
            except (TypeError, ValueError) as exc:
                raise TrackDataError(
                    f"row {row_number}: invalid Timestamp: {row.get('Timestamp')!r}"
                ) from exc

            position = (row.get("Position") or "").split(",")
            if len(position) != 2:
                raise TrackDataError(
                    f"row {row_number}: Position must be 'latitude,longitude'"
                )
            try:
                latitude, longitude = (float(part.strip()) for part in position)
            except ValueError as exc:
                raise TrackDataError(
                    f"row {row_number}: invalid Position: {row.get('Position')!r}"
                ) from exc
            if not -90.0 <= latitude <= 90.0:
                raise TrackDataError(f"row {row_number}: latitude out of range")
            if not -180.0 <= longitude <= 180.0:
                raise TrackDataError(f"row {row_number}: longitude out of range")

            points.append(
                TrackPoint(
                    timestamp=timestamp,
                    utc=_parse_utc(row.get("UTC"), timestamp, row_number=row_number),
                    callsign=(row.get("Callsign") or "").strip(),
                    latitude=latitude,
                    longitude=longitude,
                    altitude=_optional_float(
                        row.get("Altitude"), row_number=row_number, field="Altitude"
                    ),
                    speed=_optional_float(
                        row.get("Speed"), row_number=row_number, field="Speed"
                    ),
                    direction=_optional_float(
                        row.get("Direction"), row_number=row_number, field="Direction"
                    ),
                )
            )

    if len(points) < 2:
        raise TrackDataError("at least two ADS-B points are required")
    points.sort(key=lambda point: point.timestamp)
    return Track(source=source, points=tuple(points))

