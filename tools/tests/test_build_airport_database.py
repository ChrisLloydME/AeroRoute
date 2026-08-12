from __future__ import annotations

import csv
import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "build_airport_database.py"
SPEC = importlib.util.spec_from_file_location("build_airport_database", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


AIRPORT_COLUMNS = [
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
]


class AirportDatabaseBuilderTests(unittest.TestCase):
    def test_builds_filtered_searchable_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            airports_path = root / "airports.csv"
            countries_path = root / "countries.csv"
            database_path = root / "airports.sqlite"

            with countries_path.open("w", encoding="utf-8", newline="") as output:
                writer = csv.DictWriter(output, fieldnames=["code", "name"])
                writer.writeheader()
                writer.writerow({"code": "CN", "name": "China"})

            rows = [
                self.airport(
                    id="1",
                    ident="ZSPD",
                    type="large_airport",
                    name="Shanghai Pudong International Airport",
                    municipality="Shànghǎi (Pudong)",
                    scheduled_service="yes",
                    icao_code="ZSPD",
                    iata_code="PVG",
                    keywords="Shanghai, Pudong",
                ),
                self.airport(
                    id="2",
                    ident="CN-0001",
                    type="small_airport",
                    name="Private Field",
                ),
                self.airport(
                    id="3",
                    ident="ZOLD",
                    type="closed_airport",
                    name="Closed Airport",
                    icao_code="ZOLD",
                    iata_code="OLD",
                ),
                self.airport(
                    id="4",
                    ident="ZNEW",
                    type="small_airport",
                    name="Scheduled Regional Airport",
                    scheduled_service="yes",
                    icao_code="ZNEW",
                ),
            ]
            with airports_path.open("w", encoding="utf-8", newline="") as output:
                writer = csv.DictWriter(output, fieldnames=AIRPORT_COLUMNS)
                writer.writeheader()
                writer.writerows(rows)

            source_count, bundled_count = BUILDER.create_database(
                database_path, airports_path, countries_path, "fixture-v1"
            )

            self.assertEqual(source_count, 4)
            self.assertEqual(bundled_count, 2)
            connection = sqlite3.connect(database_path)
            try:
                self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone(), ("ok",))
                self.assertEqual(connection.execute("PRAGMA user_version").fetchone(), (1,))
                airport = connection.execute(
                    "SELECT name, normalized_city FROM airports WHERE iata_code = 'PVG'"
                ).fetchone()
                self.assertEqual(
                    airport,
                    ("Shanghai Pudong International Airport", "shanghai pudong"),
                )
                self.assertIsNone(
                    connection.execute(
                        "SELECT id FROM airports WHERE ident = 'CN-0001'"
                    ).fetchone()
                )
                self.assertIsNone(
                    connection.execute("SELECT id FROM airports WHERE ident = 'ZOLD'").fetchone()
                )
                metadata = dict(connection.execute("SELECT key, value FROM metadata"))
                self.assertEqual(metadata["source_version"], "fixture-v1")
                self.assertEqual(metadata["bundled_airport_count"], "2")
            finally:
                connection.close()

    @staticmethod
    def airport(**overrides: str) -> dict[str, str]:
        row = {
            "id": "0",
            "ident": "TEST",
            "type": "small_airport",
            "name": "Test Airport",
            "latitude_deg": "31.0",
            "longitude_deg": "121.0",
            "iso_country": "CN",
            "municipality": "",
            "scheduled_service": "no",
            "icao_code": "",
            "iata_code": "",
            "keywords": "",
        }
        row.update(overrides)
        return row


if __name__ == "__main__":
    unittest.main()
