# AeroRoute

AeroRoute turns ADS-B CSV flight tracks into deterministic, editable SVG world
maps. It includes a native PySide6 macOS app and a dependency-free command-line
renderer. It uses every valid input position: no sampling, deduplication, moving
average, or route reconstruction is applied.

The route is not a polyline. After equirectangular projection, every adjacent
pair of source points becomes a cubic Bézier segment in a chord-length
parameterized interpolating spline. The curve therefore passes through every
source point while showing no waypoint dots or straight-line joins.

## Quick start

Python 3.10 or newer is sufficient; there are no runtime dependencies.

```bash
python3 -m aeroroute "ADS-B Data/LX188_40a4c777.csv" \
  --output output/LX188.svg \
  --show-flight-number \
  --flight-number LX188 \
  --show-airports \
  --origin-code ZRH \
  --destination-code PVG \
  --origin-name Zurich \
  --destination-name "Shanghai Pudong"
```

The command reports the input point count and generated cubic-segment count.
For a track containing `N` points, the SVG contains `N - 1` cubic segments. It
also embeds these values as `data-source-points` and `data-curve-segments` on
the route geometry.

## Map controls

```text
--borders / --no-borders       Toggle national borders
--country-labels               Show major country names (off by default)
--show-airports                Show origin and destination labels
--show-flight-number           Show the editorial flight information block
--flight-number TEXT           Override the filename-derived flight number
--origin-code TEXT             Origin IATA/ICAO code, e.g. ZRH
--destination-code TEXT        Destination IATA/ICAO code, e.g. PVG
--origin-name TEXT             Origin label and metadata name
--destination-name TEXT        Destination label and metadata name
--waypoint-codes A,B,C         Airport codes for an ordered multi-leg map
--waypoint-names A,B,C         Airport names for an ordered multi-leg map
--route-name TEXT              Override the metadata route subtitle
--metadata-detail TEXT         Override the date/duration detail line
--width PX --height PX         SVG canvas size (default 1600 × 1000)
--scale N                      Scale the physical SVG size and all artwork
--route-width PX               Route stroke width
```

All visual colors are configurable:

```text
--ocean-color --land-color --coastline-color --border-color
--route-color --marker-color --text-color
```

To create a `16000 × 10000` SVG with every visual element enlarged in the same
10:1 proportion, keep the default design canvas and use:

```bash
python3 -m aeroroute input.csv --output output.svg --scale 10
```

The SVG keeps a `1600 × 1000` viewBox while declaring a physical size of
`16000 × 10000`. Strokes, markers, labels, and metadata therefore scale with
the map instead of becoming relatively thinner.

For the complete command reference:

```bash
python3 -m aeroroute --help
```

## macOS app

The app accepts one or more standard Flightradar24 CSV downloads. Drop files
onto the window, drag them into itinerary order, edit the airport labels, and
export SVG. For multiple legs, every file must begin near the endpoint of the
previous file. AeroRoute reports the discontinuity and disables export when the
ordered connection is greater than 50 km.

The live preview uses the same parser, projection, point set, curve generator,
and SVG renderer as the final export. Output scale defaults to 10, producing a
`16000 × 10000` SVG from the `1600 × 1000` design canvas without making the
route relatively thinner.

Build a standalone app containing Python, Qt, the SVG renderer, and map data:

```bash
chmod +x scripts/build_macos.sh
scripts/build_macos.sh universal2
```

Valid targets are `universal2`, `arm64`, and `x86_64`. The universal build runs
natively on both Apple Silicon and Intel Macs when the selected Python and all
binary wheels contain both architectures. The checked build configuration uses
macOS 13 as its minimum version and intentionally performs no Developer ID
signing or Apple notarization.

Because the app is unsigned, macOS Gatekeeper may quarantine a copy transferred
from another computer. This is expected for the requested unsigned build and is
separate from whether dependencies are bundled.

## Flightradar24 input

The import adapter recognizes the standard Flightradar24 flight-track columns:

```csv
Timestamp,UTC,Callsign,Position,Altitude,Speed,Direction
1783940888,2026-07-13T11:08:08Z,SWR188,"47.452629,8.557839",0,0,275
```

Rows are validated and then sorted by `Timestamp`. Invalid coordinates produce
an explicit error rather than being silently discarded. Repeated positions are
retained as source nodes.

The map uses a fixed equirectangular layout: longitude maps linearly to x and
latitude maps linearly to y. No Mercator scaling, great-circle bowing, or
latitude-dependent horizontal adjustment is applied. The visible map is
letterboxed and stops at 60°S, matching the clean MapChart-style composition.

## Tests

```bash
python3 -m unittest discover -s tests -v
```

The tests verify that LX188's 2,697 CSV rows produce 2,696 cubic segments, that
only the two endpoint markers are visible, and that PVG is placed from the exact
CSV endpoint (`31.133997, 121.823753`).

## Map data

The offline world outline and optional country borders use Natural Earth 1:110m
public-domain vector data. No road, terrain, or satellite layers are included.
