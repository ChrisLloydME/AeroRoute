from __future__ import annotations

import argparse
from pathlib import Path

from .model import TrackDataError, load_track
from .svg import MapStyle, RenderOptions, write_svg


def _color(value: str) -> str:
    value = value.strip()
    if not value:
        raise argparse.ArgumentTypeError("color cannot be empty")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aeroroute",
        description="Generate a deterministic SVG world map from an ADS-B CSV track.",
    )
    parser.add_argument("input", type=Path, help="ADS-B CSV file")
    parser.add_argument("-o", "--output", type=Path, required=True, help="output SVG")
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=1000)

    borders = parser.add_mutually_exclusive_group()
    borders.add_argument("--borders", dest="show_borders", action="store_true")
    borders.add_argument("--no-borders", dest="show_borders", action="store_false")
    parser.set_defaults(show_borders=True)
    parser.add_argument("--country-labels", action="store_true")
    parser.add_argument("--show-airports", action="store_true")
    parser.add_argument("--show-flight-number", action="store_true")
    parser.add_argument("--flight-number")
    parser.add_argument("--origin-code")
    parser.add_argument("--destination-code")
    parser.add_argument("--origin-name")
    parser.add_argument("--destination-name")

    parser.add_argument("--ocean-color", type=_color, default="#B2BAC3")
    parser.add_argument("--land-color", type=_color, default="#D9D9D9")
    parser.add_argument("--coastline-color", type=_color, default="#787C80")
    parser.add_argument("--border-color", type=_color, default="#A9ADB2")
    parser.add_argument("--route-color", type=_color, default="#183143")
    parser.add_argument("--marker-color", type=_color, default="#E05B45")
    parser.add_argument("--text-color", type=_color, default="#171D21")
    parser.add_argument("--route-width", type=float, default=1.2)
    parser.add_argument(
        "--font-family",
        default="Helvetica Neue, Helvetica, Arial, sans-serif",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        track = load_track(args.input)
        stats = write_svg(
            track,
            args.output,
            options=RenderOptions(
                width=args.width,
                height=args.height,
                show_borders=args.show_borders,
                show_country_labels=args.country_labels,
                show_airports=args.show_airports,
                show_flight_number=args.show_flight_number,
                flight_number=args.flight_number,
                origin_code=args.origin_code,
                destination_code=args.destination_code,
                origin_name=args.origin_name,
                destination_name=args.destination_name,
            ),
            style=MapStyle(
                ocean=args.ocean_color,
                land=args.land_color,
                coastline=args.coastline_color,
                borders=args.border_color,
                route=args.route_color,
                marker=args.marker_color,
                text=args.text_color,
                route_width=args.route_width,
                font_family=args.font_family,
            ),
        )
    except (OSError, TrackDataError, ValueError) as exc:
        parser.error(str(exc))

    print(
        f"Wrote {args.output} using {stats.source_points} source points "
        f"and {stats.curve_segments} cubic curve segments."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
