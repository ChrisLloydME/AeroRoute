from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree as ET

from aeroroute.fr24 import flight_number_from_filename, load_fr24
from aeroroute.model import TrackDataError, combine_tracks, load_track, validate_leg_order
from aeroroute.svg import RenderOptions, build_svg, write_svg


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_DATA = ROOT / "examples" / "data"
GOLDEN_DIR = ROOT / "compatibility" / "golden" / "python"
VERIFY_SCRIPT = ROOT / "compatibility" / "verify_python_golden.py"
SVG_NS = {"svg": "http://www.w3.org/2000/svg"}
HEADER = "Timestamp,UTC,Callsign,Position,Altitude,Speed,Direction\n"


class FR24ContractTests(unittest.TestCase):
    def _load_text(self, name: str, body: str):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / name
        path.write_text(body, encoding="utf-8")
        return load_fr24(path)

    def test_bom_quotes_optional_blanks_and_utc_fallback(self) -> None:
        imported = self._load_text(
            "lx188_download.csv",
            "\ufeff" + HEADER
            + '20,,"CALL,ONE","10.5,20.25",,"","   "\n'
            + '10,"2026-07-13T11:08:08Z",CALL2,"11.5,21.25",100,200,90\n',
        )
        first, second = imported.track.points
        self.assertEqual((first.timestamp, second.timestamp), (10.0, 20.0))
        self.assertEqual(second.callsign, "CALL,ONE")
        self.assertIsNone(second.altitude)
        self.assertIsNone(second.speed)
        self.assertIsNone(second.direction)
        self.assertEqual(second.utc, datetime.fromtimestamp(20, tz=timezone.utc))

    def test_timestamp_sort_is_stable_for_equal_values(self) -> None:
        imported = self._load_text(
            "sort.csv",
            HEADER
            + '2,,LATE,"0,0",,,\n'
            + '1,,FIRST,"1,1",,,\n'
            + '1,,SECOND,"2,2",,,\n',
        )
        self.assertEqual(
            [point.callsign for point in imported.track.points],
            ["FIRST", "SECOND", "LATE"],
        )

    def test_repeated_coordinates_are_retained(self) -> None:
        imported = self._load_text(
            "repeat.csv",
            HEADER
            + '1,,ONE,"10,20",,,\n'
            + '2,,TWO,"10,20",,,\n'
            + '3,,THREE,"11,21",,,\n',
        )
        coordinates = [
            (point.latitude, point.longitude) for point in imported.track.points
        ]
        self.assertEqual(coordinates, [(10.0, 20.0), (10.0, 20.0), (11.0, 21.0)])

    def test_filename_metadata_derivation(self) -> None:
        self.assertEqual(flight_number_from_filename(Path("LX188_40a4c777.csv")), "LX188")
        self.assertEqual(flight_number_from_filename(Path("sq22.csv")), "SQ22")
        self.assertEqual(flight_number_from_filename(Path("not-a-flight.csv")), "not-a-flight")

    def test_invalid_inputs_keep_exact_error_text(self) -> None:
        cases = (
            (
                "missing.csv",
                "Timestamp,Callsign\n1,A\n",
                "not a standard Flightradar24 CSV; missing columns: Position, UTC",
            ),
            (
                "timestamp.csv",
                HEADER + 'bad,,A,"1,2",,,\n' + '2,,B,"1,2",,,\n',
                "row 2: invalid Timestamp: 'bad'",
            ),
            (
                "position-shape.csv",
                HEADER + "1,,A,12,,,\n" + '2,,B,"1,2",,,\n',
                "row 2: Position must be 'latitude,longitude'",
            ),
            (
                "position-value.csv",
                HEADER + '1,,A,"north,2",,,\n' + '2,,B,"1,2",,,\n',
                "row 2: invalid Position: 'north,2'",
            ),
            (
                "latitude.csv",
                HEADER + '1,,A,"91,2",,,\n' + '2,,B,"1,2",,,\n',
                "row 2: latitude out of range",
            ),
            (
                "longitude.csv",
                HEADER + '1,,A,"1,181",,,\n' + '2,,B,"1,2",,,\n',
                "row 2: longitude out of range",
            ),
            (
                "optional.csv",
                HEADER + '1,,A,"1,2",high,,\n' + '2,,B,"1,2",,,\n',
                "row 2: invalid Altitude: 'high'",
            ),
            (
                "utc.csv",
                HEADER + '1,yesterday,A,"1,2",,,\n' + '2,,B,"1,2",,,\n',
                "row 2: invalid UTC: 'yesterday'",
            ),
            (
                "short.csv",
                HEADER + '1,,A,"1,2",,,\n',
                "at least two FR24 positions are required",
            ),
        )
        for name, contents, message in cases:
            with self.subTest(name=name):
                with self.assertRaises(TrackDataError) as raised:
                    self._load_text(name, contents)
                self.assertEqual(str(raised.exception), message)


class RouteContractTests(unittest.TestCase):
    def test_default_50_km_multi_leg_contract(self) -> None:
        paths = [
            EXAMPLE_DATA / "lh727.csv",
            EXAMPLE_DATA / "lh2440.csv",
            EXAMPLE_DATA / "fi217.csv",
        ]
        tracks = [load_track(path) for path in paths]
        distances = validate_leg_order(tracks)
        self.assertEqual(len(distances), 2)
        self.assertTrue(all(distance < 50.0 for distance in distances))

        combined = combine_tracks(paths, validate_continuity=True)
        self.assertEqual(len(combined.points), sum(len(track.points) for track in tracks))
        self.assertEqual(len(combined.waypoints), 4)
        self.assertEqual(
            combined.waypoint_indices,
            (0, len(tracks[0].points) - 1, len(tracks[0].points) + len(tracks[1].points) - 1, len(combined.points) - 1),
        )

    def test_50_km_rejection_text_and_tolerance_validation(self) -> None:
        tracks = [
            load_track(EXAMPLE_DATA / "lx188.csv"),
            load_track(EXAMPLE_DATA / "sk2596.csv"),
        ]
        with self.assertRaisesRegex(
            TrackDataError,
            r"^leg 1 does not connect to leg 2: end-to-start distance is \d+\.\d km$",
        ):
            validate_leg_order(tracks)
        with self.assertRaisesRegex(ValueError, "^continuity tolerance must be greater than zero$"):
            validate_leg_order(tracks, tolerance_km=0)

    def test_sq22_default_render_wraps_at_antimeridian(self) -> None:
        track = load_track(EXAMPLE_DATA / "sq22.csv")
        svg, stats = build_svg(track)
        root = ET.fromstring(svg)
        copies = root.findall(".//svg:g[@id='flight-track']/svg:path", SVG_NS)
        self.assertEqual([path.attrib["data-copy-shift"] for path in copies], ["-1", "0"])
        self.assertEqual(stats.source_points, len(track.points))
        self.assertEqual(stats.curve_segments, len(track.points) - 1)
        self.assertIsNone(root.find(".//svg:g[@id='airport-labels']", SVG_NS))
        self.assertIsNone(root.find(".//svg:g[@id='flight-metadata']", SVG_NS))

    def test_svg_generation_is_byte_deterministic(self) -> None:
        track = load_track(EXAMPLE_DATA / "sq22.csv")
        first, first_stats = build_svg(track, options=RenderOptions())
        second, second_stats = build_svg(track, options=RenderOptions())
        self.assertEqual(first, second)
        self.assertEqual(first_stats, second_stats)

        with tempfile.TemporaryDirectory() as directory:
            first_path = Path(directory) / "first.svg"
            second_path = Path(directory) / "second.svg"
            write_svg(track, first_path)
            write_svg(track, second_path)
            self.assertEqual(
                hashlib.sha256(first_path.read_bytes()).digest(),
                hashlib.sha256(second_path.read_bytes()).digest(),
            )


class GoldenFixtureTests(unittest.TestCase):
    @staticmethod
    def _golden_snapshot() -> dict[str, tuple[str, int, int]]:
        return {
            path.name: (
                hashlib.sha256(path.read_bytes()).hexdigest(),
                path.stat().st_size,
                path.stat().st_mtime_ns,
            )
            for path in sorted(GOLDEN_DIR.glob("*"))
            if path.is_file()
        }

    def test_default_verifier_is_read_only_and_replays_all_argv(self) -> None:
        before = self._golden_snapshot()
        completed = subprocess.run(
            [sys.executable, str(VERIFY_SCRIPT)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.count("verified "), 9)
        self.assertEqual(self._golden_snapshot(), before)

    def test_capture_requires_explicit_manual_approval(self) -> None:
        before = self._golden_snapshot()
        completed = subprocess.run(
            [sys.executable, str(VERIFY_SCRIPT), "--capture"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("requires explicit manual approval", completed.stderr)
        self.assertEqual(self._golden_snapshot(), before)

    def test_capture_is_permanently_disabled_even_with_approval_flag(self) -> None:
        before = self._golden_snapshot()
        completed = subprocess.run(
            [
                sys.executable,
                str(VERIFY_SCRIPT),
                "--capture",
                "--approve-new-baseline",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("capture is permanently disabled", completed.stderr)
        self.assertIn("restore missing files from Git", completed.stderr)
        self.assertEqual(self._golden_snapshot(), before)


if __name__ == "__main__":
    unittest.main()
