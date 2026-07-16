from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .model import Track, TrackDataError, TrackPoint


FR24_REQUIRED_COLUMNS = frozenset({"Timestamp", "UTC", "Callsign", "Position"})
FR24_OPTIONAL_COLUMNS = frozenset({"Altitude", "Speed", "Direction"})


@dataclass(frozen=True, slots=True)
class FR24Metadata:
    source: Path
    flight_number: str
    callsign: str
    row_count: int


@dataclass(frozen=True, slots=True)
class ImportedLeg:
    track: Track
    metadata: FR24Metadata


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


def flight_number_from_filename(path: Path) -> str:
    """Return the FR24 flight designator before its download identifier."""

    candidate = path.stem.split("_", 1)[0].upper().replace(" ", "")
    return candidate if re.fullmatch(r"[A-Z0-9]{2,3}\d{1,4}[A-Z]?", candidate) else path.stem


class FR24CSVAdapter:
    """Strict adapter for the standard Flightradar24 flight-track CSV export."""

    @staticmethod
    def recognizes(fieldnames: list[str] | None) -> bool:
        return FR24_REQUIRED_COLUMNS.issubset(fieldnames or ())

    def load(self, path: str | Path) -> ImportedLeg:
        source = Path(path)
        points: list[TrackPoint] = []
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if not self.recognizes(reader.fieldnames):
                missing = FR24_REQUIRED_COLUMNS.difference(reader.fieldnames or ())
                raise TrackDataError(
                    "not a standard Flightradar24 CSV; missing columns: "
                    + ", ".join(sorted(missing))
                )

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
                        altitude=_optional_float(row.get("Altitude"), row_number=row_number, field="Altitude"),
                        speed=_optional_float(row.get("Speed"), row_number=row_number, field="Speed"),
                        direction=_optional_float(row.get("Direction"), row_number=row_number, field="Direction"),
                    )
                )

        if len(points) < 2:
            raise TrackDataError("at least two FR24 positions are required")
        points.sort(key=lambda point: point.timestamp)
        track = Track(source=source, points=tuple(points), waypoint_indices=(0, len(points) - 1))
        metadata = FR24Metadata(
            source=source,
            flight_number=flight_number_from_filename(source),
            callsign=track.callsign,
            row_count=len(points),
        )
        return ImportedLeg(track=track, metadata=metadata)


def load_fr24(path: str | Path) -> ImportedLeg:
    return FR24CSVAdapter().load(path)
