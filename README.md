# AeroRoute

AeroRoute converts one or more Flightradar24/ADS-B CSV tracks into deterministic,
editable SVG world maps. It provides both a dependency-free command-line renderer
and a native PySide6 macOS app.

Every valid source position is retained. AeroRoute does not sample, smooth, or
reconstruct the track: adjacent positions are joined by an interpolating cubic
Bézier spline that passes through every input point.

## Requirements

- Python 3.10 or newer for the command-line renderer.
- PySide6 for the desktop app.
- macOS and Xcode for building the standalone `.app` bundle.

No network connection or map service is required at runtime.

## Command-line usage

Run the renderer directly from a source checkout:

```bash
python3 -m aeroroute examples/data/lx188.csv \
  --output lx188.svg \
  --show-flight-number \
  --flight-number LX188 \
  --show-airports \
  --origin-code ZRH \
  --destination-code PVG \
  --origin-name Zurich \
  --destination-name "Shanghai Pudong"
```

The command reports the input point count and generated cubic-segment count. A
track containing `N` positions produces `N - 1` cubic segments.

To install the `aeroroute` command in an isolated development environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
aeroroute --help
```

### Multi-leg routes

Pass CSV files in itinerary order. Adjacent tracks must connect within 50 km.

```bash
python3 -m aeroroute \
  examples/data/sk2596.csv \
  examples/data/lx1279.csv \
  --output kef-cph-zrh.svg \
  --show-airports \
  --show-flight-number \
  --flight-number ITINERARY \
  --waypoint-codes KEF,CPH,ZRH \
  --waypoint-names Keflavik,Copenhagen,Zurich
```

### Common options

```text
-o, --output PATH             Output SVG path (required)
--borders / --no-borders      Toggle national borders
--country-labels              Show major country names
--show-airports               Show airport and waypoint labels
--show-flight-number          Show the flight information block
--flight-number TEXT          Override the filename-derived flight number
--origin-code TEXT            Origin IATA/ICAO code
--destination-code TEXT       Destination IATA/ICAO code
--origin-name TEXT            Origin display name
--destination-name TEXT       Destination display name
--waypoint-codes A,B,C        Ordered multi-leg airport codes
--waypoint-names A,B,C        Ordered multi-leg airport names
--width PX --height PX        Design canvas size (default 1600 × 1000)
--scale N                     Physical output multiplier
--route-width PX              Route stroke width
```

Colors can be customized with `--ocean-color`, `--land-color`,
`--coastline-color`, `--border-color`, `--route-color`, `--marker-color`, and
`--text-color`. Run `python3 -m aeroroute --help` for the complete reference.

Use `--scale 10` to declare a `16000 × 10000` physical SVG while retaining the
`1600 × 1000` design viewBox and proportional artwork.

## Desktop app

Install the app dependency and launch the development version:

```bash
source .venv/bin/activate
python -m pip install -e ".[app]"
aeroroute-app
```

Drop one or more CSV files onto the window, arrange multi-leg files in itinerary
order, edit the labels and colors, then choose **Export SVG**. The preview and
export use the same parser and renderer. Export is disabled when adjacent legs
are more than 50 km apart.

## Build the macOS app

The build requires:

- macOS with the full Xcode app installed (`xcrun --find actool` must succeed).
- Python 3.10 or newer.
- A universal2 Python installation when building the default universal bundle.
- Network access on the first build to install PySide6 and PyInstaller.

Build for both Apple Silicon and Intel Macs:

```bash
scripts/build_macos.sh universal2
```

Architecture-specific builds are also supported:

```bash
scripts/build_macos.sh arm64
scripts/build_macos.sh x86_64
```

The script:

1. Creates or reuses `.venv-build`.
2. Installs the `app` and `build` extras declared in `pyproject.toml`.
3. Compiles `AppIcon.icon` with Xcode's asset compiler.
4. Runs PyInstaller using `AeroRoute.spec`.
5. Verifies the executable, Python, and Qt architecture slices.

The finished app is written to `dist/AeroRoute.app`. Intermediate files go to
`build/`. Both directories and common macOS distribution formats are ignored by
Git, so compiled app bundles are not pushed to GitHub.

To use a specific Python interpreter or build environment directory:

```bash
PYTHON_BIN=/path/to/python3 VENV_DIR=.venv-build scripts/build_macos.sh universal2
```

To verify an existing bundle separately:

```bash
scripts/verify_macos_bundle.sh dist/AeroRoute.app universal2
```

The app is intentionally unsigned and not notarized. Gatekeeper may quarantine
a bundle copied to another Mac; signing and notarization are separate release
steps and are not performed by this repository.

## CSV input

AeroRoute accepts the standard Flightradar24 columns:

```csv
Timestamp,UTC,Callsign,Position,Altitude,Speed,Direction
1783940888,2026-07-13T11:08:08Z,SWR188,"47.452629,8.557839",0,0,275
```

Rows are sorted by `Timestamp`. Invalid coordinates produce an explicit error,
and repeated positions are retained. The map uses a fixed equirectangular
projection, spans the full canvas width, and is cropped at 60°S.

## Examples

- [`examples/data`](examples/data) contains six compactly named CSV tracks used
  by the test suite and README commands.
- [`examples/output`](examples/output) contains representative rendered SVGs.
- [`examples/README.md`](examples/README.md) lists the example naming convention.

## Development and tests

Run the test suite from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

Build a wheel without changing the source tree:

```bash
python -m pip wheel . --no-deps --wheel-dir /tmp/aeroroute-wheel
```

## Repository layout

```text
aeroroute/       Python package, CLI, GUI, renderer, and bundled map data
docs/            Product and design documentation
examples/data/   Example Flightradar24 CSV tracks
examples/output/ Example SVG renders
resources/       Xcode asset catalog metadata
scripts/         macOS build and bundle-verification scripts
tests/           Unit tests
```

The offline map geometry comes from Natural Earth 1:110m public-domain data.
AeroRoute is released under the [MIT License](LICENSE).
