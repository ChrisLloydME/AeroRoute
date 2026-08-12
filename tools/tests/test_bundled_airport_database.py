from __future__ import annotations

import sqlite3
import unittest
from pathlib import Path


DATABASE_PATH = (
    Path(__file__).parents[2]
    / "AeroRouteCore"
    / "Sources"
    / "AeroRouteCore"
    / "Resources"
    / "airports.sqlite"
)


class BundledAirportDatabaseTests(unittest.TestCase):
    def test_database_integrity_and_provenance(self) -> None:
        connection = sqlite3.connect(f"file:{DATABASE_PATH}?mode=ro", uri=True)
        try:
            self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone(), (1,))
            metadata = dict(connection.execute("SELECT key, value FROM metadata"))
            self.assertEqual(metadata["source"], "OurAirports")
            self.assertEqual(metadata["source_license"], "Public Domain")
            self.assertEqual(
                int(metadata["bundled_airport_count"]),
                connection.execute("SELECT COUNT(*) FROM airports").fetchone()[0],
            )
        finally:
            connection.close()

    def test_representative_airports_and_filter(self) -> None:
        connection = sqlite3.connect(f"file:{DATABASE_PATH}?mode=ro", uri=True)
        try:
            airports = dict(
                connection.execute(
                    """
                    SELECT iata_code, icao_code
                    FROM airports
                    WHERE iata_code IN ('JFK', 'LHR', 'PVG')
                    """
                )
            )
            self.assertEqual(
                airports,
                {"JFK": "KJFK", "LHR": "EGLL", "PVG": "ZSPD"},
            )
            self.assertEqual(
                connection.execute(
                    "SELECT COUNT(*) FROM airports WHERE airport_type = 'closed_airport'"
                ).fetchone(),
                (0,),
            )
            self.assertGreater(
                connection.execute(
                    "SELECT COUNT(*) FROM airports WHERE iata_code IS NOT NULL"
                ).fetchone()[0],
                8_000,
            )
            self.assertEqual(
                connection.execute(
                    """
                    SELECT COUNT(*)
                    FROM airports
                    WHERE iata_code IS NULL
                      AND scheduled_service = 0
                      AND airport_type NOT IN ('medium_airport', 'large_airport')
                    """
                ).fetchone(),
                (0,),
            )
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
