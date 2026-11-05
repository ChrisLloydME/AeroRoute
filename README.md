# AeroRoute

AeroRoute is a native SwiftUI application for macOS, iPhone, and iPad. It turns
one or more Flightradar24 CSV tracks into deterministic, editable SVG world
maps. All parsing, validation, geometry, and SVG generation live in the shared
`AeroRouteCore` Swift Package and run fully offline.

Every valid source position is retained. AeroRoute does not sample or discard
track data. Each continuous path with `N` input positions produces `N - 1`
interpolating cubic Bézier segments. Multiple independent legs can share one
map; adjacent legs within 50 km are drawn as a continuous route.

## Requirements

- macOS with Xcode 27.
- The repository checkout; there are no third-party runtime dependencies.

The shipping application does not require Python, PySide6, PyInstaller, a map
service, or a network connection.

## Open and run

Open [macos/AeroRoute/AeroRoute.xcodeproj](macos/AeroRoute/AeroRoute.xcodeproj)
in Xcode 27 and select the shared `AeroRoute` scheme. The same target adapts to
macOS, iPhone, and iPad and uses `AeroRouteCore` on every platform.

In the app:

1. Import or drop one or more Flightradar24 CSV files in display order.
2. Reorder or remove legs; connectable neighbors form continuous route paths.
3. Edit labels, map content, dimensions, scale, colors, and route width.
4. Review the live SVG preview and leg table.
5. Export the deterministic SVG with the system save panel.

## CSV input contract

AeroRoute accepts the standard Flightradar24 columns:

```csv
Timestamp,UTC,Callsign,Position,Altitude,Speed,Direction
1783940888,2026-07-13T11:08:08Z,SWR188,"47.452629,8.557839",0,0,275
```

Rows are parsed as RFC 4180 CSV and sorted stably by `Timestamp`. Optional
fields may be blank or absent where the reference accepted them. Invalid or
out-of-range coordinates are rejected explicitly, repeated positions are
retained, and filename-derived flight metadata follows the original contract.

## Build and test

If Xcode 27 is installed as `Xcode-beta.app`, select it per command without
changing the system-wide developer directory:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Run the shared core tests:

```bash
swift test --package-path AeroRouteCore
```

Build and test the macOS application:

```bash
xcodebuild \
  -project macos/AeroRoute/AeroRoute.xcodeproj \
  -scheme AeroRoute \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project macos/AeroRoute/AeroRoute.xcodeproj \
  -scheme AeroRoute \
  -destination 'platform=macOS' \
  test
```

Compile the unsigned generic iPhone/iPad device target without starting a
simulator:

```bash
xcodebuild \
  -project macos/AeroRoute/AeroRoute.xcodeproj \
  -scheme AeroRoute \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Regression fixtures and archive

`examples/data` contains seven fixed Flightradar24 CSV inputs used by the core,
application, and UI tests. `examples/output` holds the nine immutable SVG
baselines checked byte-for-byte by `GoldenCompatibilityTests`. Keep these
fixtures when running tests; do not update them to make a failing comparison pass.

The original renderer's capture metadata is preserved in
`examples/output/manifest.json`. Its commands and paths describe the historical
capture environment, rather than commands to run in the current checkout.

The pre-native Python/Qt application, CLI, packaging scripts, and duplicate data
were removed from `main`. The complete tracked state before cleanup is retained
on `codex/archive-before-native-cleanup-2026-11-05` (commit `89a70dd`).

`tools/build_airport_database.py` and its tests remain because they generate and
validate the native app's bundled airport catalog. They use the Python standard
library and are maintenance tools, not part of the application runtime. See
[the airport data procedure](docs/airport-data.md).

## Repository layout

```text
AeroRouteCore/
├── Sources/AeroRouteCore/
│   ├── Airports/               Airport catalog, location, and search
│   ├── FlightTracks/           FR24 parsing and track models
│   ├── Map/                    GeoJSON loading and route geometry
│   ├── SVG/                    SVG rendering and XML serialization
│   └── Resources/              Bundled map and airport data
└── Tests/AeroRouteCoreTests/   Tests grouped by the same responsibilities
macos/AeroRoute/
├── AeroRoute.xcodeproj/        Shared Xcode 27 project
└── AeroRoute/
    ├── App/                    Application and root view entry points
    ├── Features/               Route editing and SVG preview UI
    ├── Services/               Export integrations
    ├── Support/                Shared UI helpers
    └── Assets.xcassets/        Application assets
examples/
├── data/                       Fixed Flightradar24 CSV inputs
└── output/                     Immutable SVG baselines and capture metadata
docs/                           Product and architecture documentation
tools/                          Airport database build and validation tools
```

Generated builds, derived data, package caches, virtual environments, and
editor metadata are intentionally ignored and should stay outside the tracked
repository structure.

The offline map geometry comes from Natural Earth 1:110m public-domain data.
AeroRoute is released under the [MIT License](LICENSE).
