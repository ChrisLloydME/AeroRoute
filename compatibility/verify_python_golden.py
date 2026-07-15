#!/usr/bin/env python3
"""Verify immutable SVG output from the captured Python reference renderer.

Verification writes only to a temporary directory. The historical capture
flags remain as an explicit safety gate, but committed baselines can never be
created or rewritten by this tool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
GOLDEN_DIR = ROOT / "compatibility" / "golden" / "python"
MANIFEST_PATH = GOLDEN_DIR / "manifest.json"
SVG_NS = "http://www.w3.org/2000/svg"
GENERATOR_ENVIRONMENT = {
    "LC_ALL": "C",
    "PYTHONHASHSEED": "0",
    "PYTHONUTF8": "1",
    "PYTHONDONTWRITEBYTECODE": "1",
}
sys.dont_write_bytecode = True


@dataclass(frozen=True, slots=True)
class FixtureSpec:
    fixture_id: str
    inputs: tuple[str, ...]
    output: str
    cli_options: tuple[str, ...]
    contract_status: str
    note: str

    def argv(self) -> list[str]:
        return [
            "python3",
            "-m",
            "aeroroute",
            *self.inputs,
            "-o",
            f"compatibility/golden/python/{self.output}",
            *self.cli_options,
        ]


SPECS = (
    FixtureSpec(
        "single-fi217",
        ("examples/data/fi217.csv",),
        "flight-fi217.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "FI217", "--origin-code", "CPH",
            "--destination-code", "KEF", "--origin-name", "Copenhagen",
            "--destination-name", "Keflavik",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-lh2440",
        ("examples/data/lh2440.csv",),
        "flight-lh2440.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "LH2440", "--origin-code", "MUC",
            "--destination-code", "CPH", "--origin-name", "Munich",
            "--destination-name", "Copenhagen",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-lh727",
        ("examples/data/lh727.csv",),
        "flight-lh727.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "LH727", "--origin-code", "PVG",
            "--destination-code", "MUC", "--origin-name", "Shanghai Pudong",
            "--destination-name", "Munich",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-lx1279",
        ("examples/data/lx1279.csv",),
        "flight-lx1279.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "LX1279", "--origin-code", "CPH",
            "--destination-code", "ZRH", "--origin-name", "Copenhagen",
            "--destination-name", "Zurich",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-lx188",
        ("examples/data/lx188.csv",),
        "flight-lx188.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "LX188", "--origin-code", "ZRH",
            "--destination-code", "PVG", "--origin-name", "Zurich",
            "--destination-name", "Shanghai Pudong",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-sk2596",
        ("examples/data/sk2596.csv",),
        "flight-sk2596.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "SK2596", "--origin-code", "KEF",
            "--destination-code", "CPH", "--origin-name", "Keflavik",
            "--destination-name", "Copenhagen",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative SVG.",
    ),
    FixtureSpec(
        "single-sq22-antimeridian",
        ("examples/data/sq22.csv",),
        "flight-sq22.svg",
        (),
        "new-unreviewed-antimeridian-coverage",
        "Default output options only. This locks antimeridian geometry and does not claim reviewed SQ22 labels.",
    ),
    FixtureSpec(
        "itinerary-kef-cph-zrh-pvg",
        (
            "examples/data/sk2596.csv",
            "examples/data/lx1279.csv",
            "examples/data/lx188.csv",
        ),
        "itinerary-kef-cph-zrh-pvg.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "KEF–CPH–ZRH–PVG", "--waypoint-codes",
            "KEF,CPH,ZRH,PVG", "--waypoint-names",
            "Keflavik,Copenhagen,Zurich,Shanghai Pudong", "--metadata-detail",
            "SK2596 · LX1279 · LX188",
        ),
        "existing-reviewed-output-options",
        "Options reconstructed from the existing representative itinerary SVG.",
    ),
    FixtureSpec(
        "itinerary-pvg-muc-cph-kef",
        (
            "examples/data/lh727.csv",
            "examples/data/lh2440.csv",
            "examples/data/fi217.csv",
        ),
        "itinerary-pvg-muc-cph-kef.svg",
        (
            "--scale", "10", "--show-airports", "--show-flight-number",
            "--flight-number", "PVG–MUC–CPH–KEF", "--waypoint-codes",
            "PVG,MUC,CPH,KEF", "--waypoint-names",
            "Shanghai Pudong,Munich,Copenhagen,Keflavik", "--metadata-detail",
            "LH727 · LH2440 · FI213",
        ),
        "existing-reviewed-output-options",
        "FI213 is intentionally preserved as the reviewed metadata-detail contract even though the input filename is fi217.csv.",
    ),
)

GEOJSON_PATHS = (
    "aeroroute/data/ne_110m_land.geojson",
    "aeroroute/data/ne_110m_admin_0_countries.geojson",
)


class VerificationError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolved_options(spec: FixtureSpec) -> dict[str, Any]:
    from aeroroute.cli import build_parser
    from aeroroute.svg import MapStyle, RenderOptions

    args = build_parser().parse_args(spec.argv()[3:])
    render = RenderOptions(
        width=args.width,
        height=args.height,
        scale=args.scale,
        show_borders=args.show_borders,
        show_country_labels=args.country_labels,
        show_airports=args.show_airports,
        show_flight_number=args.show_flight_number,
        flight_number=args.flight_number,
        origin_code=args.origin_code,
        destination_code=args.destination_code,
        origin_name=args.origin_name,
        destination_name=args.destination_name,
        waypoint_codes=tuple(
            value.strip()
            for value in (args.waypoint_codes or "").split(",")
            if value.strip()
        ),
        waypoint_names=tuple(
            value.strip()
            for value in (args.waypoint_names or "").split(",")
            if value.strip()
        ),
        route_name=args.route_name,
        metadata_detail=args.metadata_detail,
    )
    style = MapStyle(
        ocean=args.ocean_color,
        land=args.land_color,
        coastline=args.coastline_color,
        borders=args.border_color,
        route=args.route_color,
        marker=args.marker_color,
        text=args.text_color,
        route_width=args.route_width,
        font_family=args.font_family,
    )
    # Match the JSON representation stored in the manifest (tuples become arrays).
    return json.loads(
        json.dumps({"render_options": asdict(render), "map_style": asdict(style)})
    )


def _inspect_svg(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    geometry = root.find(f".//{{{SVG_NS}}}path[@id='flight-track-geometry']")
    route = root.find(f".//{{{SVG_NS}}}g[@id='flight-track']")
    markers = root.find(f".//{{{SVG_NS}}}g[@id='endpoint-markers']")
    if geometry is None or route is None or markers is None:
        raise VerificationError(f"{path}: required SVG route elements are missing")
    route_paths = route.findall(f"./{{{SVG_NS}}}path")
    copy_shifts = [int(node.attrib["data-copy-shift"]) for node in route_paths]
    waypoint_count = len(markers.findall(f"./{{{SVG_NS}}}circle"))
    points = int(geometry.attrib["data-source-points"])
    segments = int(geometry.attrib["data-curve-segments"])
    if geometry.attrib["d"].count("C ") != segments:
        raise VerificationError(f"{path}: cubic command count does not match metadata")
    return {
        "points": points,
        "segments": segments,
        "copy_shifts": copy_shifts,
        "waypoint_count": waypoint_count,
    }


def _run_cli(spec: FixtureSpec, destination: Path) -> str:
    argv = spec.argv()
    output_index = argv.index("-o") + 1
    argv[output_index] = str(destination)
    environment = os.environ.copy()
    environment.update(GENERATOR_ENVIRONMENT)
    completed = subprocess.run(
        [sys.executable, *argv[1:]],
        cwd=ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode:
        raise VerificationError(
            f"{spec.fixture_id}: renderer exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed.stdout.strip()


def _expect_equal(actual: Any, expected: Any, context: str) -> None:
    if actual != expected:
        raise VerificationError(
            f"{context} mismatch:\nexpected {expected!r}\nactual   {actual!r}"
        )


def verify() -> None:
    if not MANIFEST_PATH.is_file():
        raise VerificationError(f"missing golden manifest: {MANIFEST_PATH}")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    _expect_equal(manifest.get("schema_version"), 1, "manifest schema_version")

    environment = manifest.get("generator_environment", {})
    for key in ("python", "element_tree", "locale", "process_environment"):
        if not isinstance(environment.get(key), dict) or not environment[key]:
            raise VerificationError(f"manifest generator_environment.{key} is missing")

    expected_geojson = [
        {"path": path, "sha256": _sha256(ROOT / path)} for path in GEOJSON_PATHS
    ]
    _expect_equal(manifest.get("geojson"), expected_geojson, "GeoJSON inputs")

    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list):
        raise VerificationError("manifest fixtures must be a list")
    _expect_equal(
        [fixture.get("id") for fixture in fixtures],
        [spec.fixture_id for spec in SPECS],
        "fixture order",
    )

    with tempfile.TemporaryDirectory(prefix="aeroroute-python-golden-") as directory:
        temporary = Path(directory)
        for spec, fixture in zip(SPECS, fixtures, strict=True):
            _expect_equal(fixture.get("contract_status"), spec.contract_status, f"{spec.fixture_id} contract_status")
            _expect_equal(fixture.get("note"), spec.note, f"{spec.fixture_id} note")
            _expect_equal(fixture.get("argv"), spec.argv(), f"{spec.fixture_id} argv")
            _expect_equal(
                fixture.get("resolved_options"),
                _resolved_options(spec),
                f"{spec.fixture_id} resolved options",
            )

            expected_inputs = [
                {"path": path, "sha256": _sha256(ROOT / path)}
                for path in spec.inputs
            ]
            _expect_equal(fixture.get("inputs"), expected_inputs, f"{spec.fixture_id} inputs")

            golden_path = GOLDEN_DIR / spec.output
            if not golden_path.is_file():
                raise VerificationError(f"{spec.fixture_id}: missing golden {golden_path}")
            output = fixture.get("output", {})
            _expect_equal(
                output.get("path"),
                f"compatibility/golden/python/{spec.output}",
                f"{spec.fixture_id} output path",
            )
            golden_hash = _sha256(golden_path)
            _expect_equal(golden_hash, output.get("sha256"), f"{spec.fixture_id} golden hash")
            golden_stats = _inspect_svg(golden_path)
            _expect_equal(golden_stats, fixture.get("statistics"), f"{spec.fixture_id} golden statistics")

            generated_path = temporary / spec.output
            command_output = _run_cli(spec, generated_path)
            generated_hash = _sha256(generated_path)
            _expect_equal(generated_hash, golden_hash, f"{spec.fixture_id} regenerated hash")
            _expect_equal(
                _inspect_svg(generated_path),
                golden_stats,
                f"{spec.fixture_id} regenerated statistics",
            )
            print(
                f"verified {spec.fixture_id}: sha256={golden_hash} "
                f"points={golden_stats['points']} segments={golden_stats['segments']} "
                f"copy_shifts={golden_stats['copy_shifts']} "
                f"waypoints={golden_stats['waypoint_count']} ({command_output})"
            )


def capture(*, approved: bool) -> None:
    if not approved:
        raise VerificationError(
            "capture requires explicit manual approval; rerun with "
            "--capture --approve-new-baseline only after a human has reviewed the inputs and options"
        )
    raise VerificationError(
        "capture is permanently disabled in the committed verifier: the reviewed "
        "golden baseline is immutable; restore missing files from Git instead of "
        "creating or rewriting them"
    )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify immutable Python SVG golden fixtures without modifying them.",
    )
    parser.add_argument(
        "--capture",
        action="store_true",
        help="deprecated safety gate; committed baselines can never be captured or rewritten",
    )
    parser.add_argument(
        "--approve-new-baseline",
        action="store_true",
        help="record that a human explicitly approved a brand-new capture",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)
    if args.approve_new_baseline and not args.capture:
        raise SystemExit("--approve-new-baseline is only valid with --capture")
    try:
        if args.capture:
            capture(approved=args.approve_new_baseline)
        else:
            verify()
    except (OSError, ValueError, VerificationError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
