# AeroRoute

AeroRoute turns ADS-B CSV flight tracks into deterministic, editable SVG world
maps. It uses every valid input position: no sampling, deduplication, moving
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
--width PX --height PX         SVG canvas size (default 1600 × 1000)
--route-width PX               Route stroke width
```

All visual colors are configurable:

```text
--ocean-color --land-color --coastline-color --border-color
--route-color --marker-color --text-color
```

For the complete command reference:

```bash
python3 -m aeroroute --help
```

## Input format

The imported repository data already uses the expected columns:

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
