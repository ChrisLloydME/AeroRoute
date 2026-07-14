from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

from aeroroute.geometry import interpolating_bezier_path, project
from aeroroute.fr24 import load_fr24
from aeroroute.model import TrackDataError, combine_tracks, load_track, validate_leg_order
from aeroroute.svg import MapStyle, RenderOptions, build_svg, write_svg

ROOT = Path(__file__).resolve().parents[1]
LX188 = ROOT / "ADS-B Data" / "LX188_40a4c777.csv"
SVG_NS = {"svg": "http://www.w3.org/2000/svg"}


class TrackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.track = load_track(LX188)

    def test_loads_every_csv_row(self) -> None:
        with LX188.open(encoding="utf-8") as handle:
            csv_points = sum(1 for _ in handle) - 1
        self.assertEqual(len(self.track.points), csv_points)
        self.assertEqual(len(self.track.points), 2697)

    def test_standard_fr24_adapter_extracts_download_metadata(self) -> None:
        imported = load_fr24(LX188)
        self.assertEqual(imported.metadata.flight_number, "LX188")
        self.assertEqual(imported.metadata.callsign, "SWR188")
        self.assertEqual(imported.metadata.row_count, 2697)

    def test_curve_uses_one_cubic_segment_per_adjacent_pair(self) -> None:
        points = [(0.0, 0.0), (1.0, 2.0), (3.0, 1.0), (4.0, 4.0)]
        path, segments = interpolating_bezier_path(points)
        self.assertEqual(segments, len(points) - 1)
        self.assertEqual(path.count("C "), len(points) - 1)
        for x, y in points[1:]:
            self.assertRegex(path, rf"{x:g} {y:g}(?: C|$)")

    def test_projection_is_strictly_flat(self) -> None:
        x_low, _ = project(120.0, -40.0, 1600, 1000)
        x_high, _ = project(120.0, 70.0, 1600, 1000)
        _, y_west = project(-150.0, 30.0, 1600, 1000)
        _, y_east = project(150.0, 30.0, 1600, 1000)
        self.assertEqual(x_low, x_high)
        self.assertEqual(y_west, y_east)

    def test_physical_scale_enlarges_all_artwork_proportionally(self) -> None:
        svg, _ = build_svg(self.track, options=RenderOptions(scale=10))
        root = ET.fromstring(svg)
        self.assertEqual(root.attrib["width"], "16000")
        self.assertEqual(root.attrib["height"], "10000")
        self.assertEqual(root.attrib["viewBox"], "0 0 1600 1000")
        route = root.find(".//svg:g[@id='flight-track']", SVG_NS)
        self.assertIsNotNone(route)
        assert route is not None
        self.assertNotIn("vector-effect", route.attrib)

    def test_svg_has_all_nodes_but_only_two_visible_point_markers(self) -> None:
        svg, stats = build_svg(
            self.track,
            options=RenderOptions(
                show_airports=True,
                show_flight_number=True,
                flight_number="LX188",
                origin_code="ZRH",
                destination_code="PVG",
                origin_name="Zurich",
                destination_name="Shanghai Pudong",
            ),
        )
        root = ET.fromstring(svg)
        geometry = root.find(".//svg:path[@id='flight-track-geometry']", SVG_NS)
        self.assertIsNotNone(geometry)
        assert geometry is not None
        self.assertEqual(int(geometry.attrib["data-source-points"]), 2697)
        self.assertEqual(int(geometry.attrib["data-curve-segments"]), 2696)
        self.assertEqual(geometry.attrib["d"].count("C "), 2696)
        self.assertEqual(len(root.findall(".//svg:circle", SVG_NS)), 2)
        markers = root.findall(".//svg:circle", SVG_NS)
        self.assertEqual(markers[0].attrib["r"], markers[1].attrib["r"])
        self.assertEqual(markers[0].attrib["fill"], markers[1].attrib["fill"])
        self.assertNotIn("stroke", markers[0].attrib)
        self.assertNotIn("stroke", markers[1].attrib)
        labels = " ".join(
            element.text or "" for element in root.findall(".//svg:text", SVG_NS)
        )
        self.assertIn("PVG · Shanghai Pudong", labels)
        self.assertEqual(stats.source_points, 2697)
        self.assertEqual(stats.curve_segments, 2696)

    def test_pvg_marker_uses_csv_coordinate_exactly(self) -> None:
        svg, _ = build_svg(self.track)
        root = ET.fromstring(svg)
        marker = root.find(".//svg:circle[@id='destination-marker']", SVG_NS)
        self.assertIsNotNone(marker)
        assert marker is not None
        self.assertEqual(marker.attrib["data-latitude"], "31.133997")
        self.assertEqual(marker.attrib["data-longitude"], "121.823753")
        expected_x, expected_y = project(121.823753, 31.133997, 1600, 1000)
        self.assertAlmostEqual(float(marker.attrib["cx"]), expected_x, places=5)
        self.assertAlmostEqual(float(marker.attrib["cy"]), expected_y, places=5)

    def test_writes_standalone_svg(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "flight.svg"
            stats = write_svg(self.track, output)
            self.assertTrue(output.is_file())
            self.assertGreater(output.stat().st_size, 100_000)
            self.assertEqual(stats.source_points, 2697)

    def test_combined_itinerary_keeps_all_leg_points_and_waypoints(self) -> None:
        itinerary = combine_tracks(
            [
                ROOT / "ADS-B Data" / "SK2596_40a24106.csv",
                ROOT / "ADS-B Data" / "LX1279_40a80dc2.csv",
            ],
            source_name="KEF-CPH-ZRH",
        )
        svg, stats = build_svg(
            itinerary,
            options=RenderOptions(
                show_airports=True,
                waypoint_codes=("KEF", "CPH", "ZRH"),
                waypoint_names=("Keflavik", "Copenhagen", "Zurich"),
            ),
        )
        root = ET.fromstring(svg)
        self.assertEqual(stats.source_points, 645 + 431)
        self.assertEqual(stats.curve_segments, stats.source_points - 1)
        self.assertEqual(len(root.findall(".//svg:circle", SVG_NS)), 3)
        self.assertIsNotNone(root.find(".//svg:circle[@id='waypoint-marker-1']", SVG_NS))

    def test_ordered_itinerary_validates_end_to_start_connections(self) -> None:
        connected = [
            load_track(ROOT / "ADS-B Data" / "SK2596_40a24106.csv"),
            load_track(ROOT / "ADS-B Data" / "LX1279_40a80dc2.csv"),
        ]
        distances = validate_leg_order(connected)
        self.assertEqual(len(distances), 1)
        self.assertLess(distances[0], 1.0)
        with self.assertRaises(TrackDataError):
            validate_leg_order(list(reversed(connected)))

    def test_map_layers_and_colors_are_configurable(self) -> None:
        svg, _ = build_svg(
            self.track,
            options=RenderOptions(show_borders=False, show_country_labels=False),
            style=MapStyle(ocean="#010203", land="#F0F1F2", route="#AABBCC"),
        )
        root = ET.fromstring(svg)
        self.assertIsNone(root.find(".//svg:path[@id='country-borders']", SVG_NS))
        ocean = root.find(".//svg:rect[@id='ocean']", SVG_NS)
        land = root.find(".//svg:path[@id='land']", SVG_NS)
        route = root.find(".//svg:g[@id='flight-track']", SVG_NS)
        assert ocean is not None and land is not None and route is not None
        self.assertEqual(ocean.attrib["fill"], "#010203")
        self.assertEqual(ocean.attrib["x"], "0")
        self.assertEqual(ocean.attrib["y"], "0")
        self.assertEqual(ocean.attrib["width"], "1600")
        self.assertEqual(ocean.attrib["height"], "1000")
        self.assertIn("background-color:#010203", root.attrib["style"])
        background = root.find("./svg:g[@id='background']", SVG_NS)
        map_layers = root.find("./svg:g[@id='map-layers']", SVG_NS)
        self.assertIsNotNone(background)
        self.assertIsNotNone(map_layers)
        assert map_layers is not None
        self.assertIsNotNone(map_layers.find("./svg:path[@id='land']", SVG_NS))
        self.assertIsNone(root.find("./svg:path[@id='land']", SVG_NS))
        self.assertEqual(land.attrib["fill"], "#F0F1F2")
        self.assertEqual(route.attrib["stroke"], "#AABBCC")
        self.assertEqual(route.attrib["stroke-width"], "1.2")


if __name__ == "__main__":
    unittest.main()
