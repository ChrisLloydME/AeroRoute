#!/usr/bin/env python3
"""Build AeroRoute's bundled airport database from local OurAirports CSV files.

This tool intentionally performs no network access. Downloading or otherwise
selecting an upstream snapshot is a separate, explicit maintenance step.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sqlite3
import tempfile
import unicodedata
from pathlib import Path


SCHEMA_VERSION = 1
ROUTE_AIRPORT_TYPES = frozenset({"large_airport", "medium_airport"})
REQUIRED_AIRPORT_COLUMNS = frozenset(
    {
        "id",
        "ident",
        "type",
        "name",
        "latitude_deg",
        "longitude_deg",
        "iso_country",
        "municipality",
        "scheduled_service",
        "icao_code",
        "iata_code",
        "keywords",
    }
)
REQUIRED_COUNTRY_COLUMNS = frozenset({"code", "name"})


def normalized_search_text(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value.casefold())
    without_marks = "".join(
        character
        for character in decomposed
        if unicodedata.category(character) != "Mn"
    )
    return " ".join(re.findall(r"[\w]+", without_marks, flags=re.UNICODE))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_columns(fieldnames: list[str] | None, required: frozenset[str], path: Path) -> None:
    actual = set(fieldnames or [])
    missing = sorted(required - actual)
    if missing:
        raise ValueError(f"{path}: missing required columns: {', '.join(missing)}")


def optional_code(value: str) -> str | None:
    cleaned = value.strip().upper()
    return cleaned or None


def should_include_airport(row: dict[str, str]) -> bool:
    if row["type"] == "closed_airport":
        return False
    return bool(
        row["iata_code"].strip()
        or row["scheduled_service"] == "yes"
        or row["type"] in ROUTE_AIRPORT_TYPES
    )


def read_countries(path: Path) -> list[tuple[str, str]]:
    countries: list[tuple[str, str]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        require_columns(reader.fieldnames, REQUIRED_COUNTRY_COLUMNS, path)
        for line_number, row in enumerate(reader, start=2):
            code = row["code"].strip().upper()
            name = row["name"].strip()
            if not code or not name:
                raise ValueError(f"{path}:{line_number}: country code and name are required")
            countries.append((code, name))
    if not countries:
        raise ValueError(f"{path}: no countries found")
    return sorted(countries)


def read_airports(
    path: Path, country_codes: set[str]
) -> tuple[list[tuple[object, ...]], int]:
    airports: list[tuple[object, ...]] = []
    source_count = 0
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        require_columns(reader.fieldnames, REQUIRED_AIRPORT_COLUMNS, path)
        for line_number, row in enumerate(reader, start=2):
            source_count += 1
            if not should_include_airport(row):
                continue

            try:
                airport_id = int(row["id"])
                latitude = float(row["latitude_deg"])
                longitude = float(row["longitude_deg"])
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: invalid numeric value") from error

            if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
                raise ValueError(f"{path}:{line_number}: coordinates out of range")

            country_code = row["iso_country"].strip().upper()
            if country_code not in country_codes:
                raise ValueError(
                    f"{path}:{line_number}: unknown country code {country_code!r}"
                )

            ident = row["ident"].strip()
            name = row["name"].strip()
            municipality = row["municipality"].strip() or None
            keywords = row["keywords"].strip() or None
            iata_code = optional_code(row["iata_code"])
            icao_code = optional_code(row["icao_code"])
            if not ident or not name:
                raise ValueError(f"{path}:{line_number}: airport ident and name are required")
            if iata_code is not None and len(iata_code) != 3:
                raise ValueError(f"{path}:{line_number}: invalid IATA code {iata_code!r}")
            if icao_code is not None and len(icao_code) != 4:
                raise ValueError(f"{path}:{line_number}: invalid ICAO code {icao_code!r}")

            search_text = normalized_search_text(
                " ".join(
                    value
                    for value in (name, municipality, iata_code, icao_code, keywords)
                    if value
                )
            )
            airports.append(
                (
                    airport_id,
                    ident,
                    name,
                    normalized_search_text(name),
                    country_code,
                    municipality,
                    normalized_search_text(municipality or ""),
                    iata_code,
                    icao_code,
                    latitude,
                    longitude,
                    row["type"],
                    1 if row["scheduled_service"] == "yes" else 0,
                    keywords,
                    search_text,
                )
            )

    if not airports:
        raise ValueError(f"{path}: no airports matched the route-airport filter")
    return sorted(airports, key=lambda airport: int(airport[0])), source_count


def create_database(
    database_path: Path,
    airports_path: Path,
    countries_path: Path,
    source_version: str,
) -> tuple[int, int]:
    countries = read_countries(countries_path)
    airports, source_count = read_airports(
        airports_path, {country[0] for country in countries}
    )

    connection = sqlite3.connect(database_path)
    try:
        connection.executescript(
            f"""
            PRAGMA application_id = 0x4145524F;
            PRAGMA user_version = {SCHEMA_VERSION};
            PRAGMA page_size = 4096;

            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;

            CREATE TABLE countries (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL
            ) WITHOUT ROWID;

            CREATE TABLE airports (
                id INTEGER PRIMARY KEY,
                ident TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                country_code TEXT NOT NULL REFERENCES countries(code),
                municipality TEXT,
                normalized_city TEXT NOT NULL,
                iata_code TEXT,
                icao_code TEXT,
                latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
                longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
                airport_type TEXT NOT NULL,
                scheduled_service INTEGER NOT NULL CHECK(scheduled_service IN (0, 1)),
                keywords TEXT,
                search_text TEXT NOT NULL
            );

            CREATE UNIQUE INDEX airports_iata_unique
                ON airports(iata_code) WHERE iata_code IS NOT NULL;
            CREATE UNIQUE INDEX airports_icao_unique
                ON airports(icao_code) WHERE icao_code IS NOT NULL;
            CREATE INDEX airports_country_city
                ON airports(country_code, normalized_city);
            CREATE INDEX airports_normalized_name
                ON airports(normalized_name);
            CREATE INDEX airports_coordinates
                ON airports(latitude, longitude);
            """
        )
        connection.executemany("INSERT INTO countries(code, name) VALUES (?, ?)", countries)
        connection.executemany(
            """
            INSERT INTO airports(
                id, ident, name, normalized_name, country_code, municipality,
                normalized_city, iata_code, icao_code, latitude, longitude,
                airport_type, scheduled_service, keywords, search_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            airports,
        )
        metadata = {
            "schema_version": str(SCHEMA_VERSION),
            "source": "OurAirports",
            "source_url": "https://ourairports.com/data/",
            "source_license": "Public Domain",
            "source_version": source_version,
            "airports_csv_sha256": sha256(airports_path),
            "countries_csv_sha256": sha256(countries_path),
            "source_airport_count": str(source_count),
            "bundled_airport_count": str(len(airports)),
            "filter": (
                "type != closed_airport AND "
                "(iata_code != empty OR scheduled_service = yes OR "
                "type IN (medium_airport, large_airport))"
            ),
        }
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)", sorted(metadata.items())
        )
        connection.commit()
        result = connection.execute("PRAGMA integrity_check").fetchone()
        if result != ("ok",):
            raise RuntimeError(f"SQLite integrity check failed: {result!r}")
        connection.execute("VACUUM")
    finally:
        connection.close()

    return source_count, len(airports)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--airports", required=True, type=Path, help="local airports.csv")
    parser.add_argument("--countries", required=True, type=Path, help="local countries.csv")
    parser.add_argument("--output", required=True, type=Path, help="output SQLite file")
    parser.add_argument(
        "--source-version",
        required=True,
        help="human-readable upstream snapshot date or version",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    airports_path = arguments.airports.resolve()
    countries_path = arguments.countries.resolve()
    output_path = arguments.output.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    temporary_fd, temporary_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.", suffix=".tmp", dir=output_path.parent
    )
    os.close(temporary_fd)
    temporary_path = Path(temporary_name)
    try:
        source_count, bundled_count = create_database(
            temporary_path,
            airports_path,
            countries_path,
            arguments.source_version,
        )
        os.replace(temporary_path, output_path)
        output_path.chmod(0o644)
    finally:
        temporary_path.unlink(missing_ok=True)

    print(
        f"Built {output_path} with {bundled_count:,} of {source_count:,} "
        "OurAirports records"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
