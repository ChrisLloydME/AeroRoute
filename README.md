# AeroRoute

AeroRoute is a native SwiftUI application for macOS, iPhone, and iPad. It turns
one or more Flightradar24 CSV tracks into deterministic, editable SVG world
maps. All parsing, validation, geometry, and SVG generation live in the shared
`AeroRouteCore` Swift Package and run fully offline.

Every valid source position is retained. AeroRoute does not sample, smooth, or
reconstruct a track: `N` input positions produce `N - 1` interpolating cubic
Bézier segments. Adjacent itinerary legs must connect within 50 km.

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

1. Import or drop one or more Flightradar24 CSV files in itinerary order.
2. Reorder or remove legs and validate their endpoint continuity.
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

Developer ID signing, provisioning, notarization, TestFlight, and App Store
publication are intentionally outside this migration. They are not required to
build, test, or complete the application locally.

## Compatibility evidence

`compatibility/golden/python` contains nine immutable SVG fixtures captured
from the reviewed Python renderer, plus the commands, options, input hashes, and
output hashes that produced them. `AeroRouteCore` regenerates every fixture
byte-for-byte in `GoldenCompatibilityTests`; the golden files must not be
updated to make a failing Swift comparison pass.

The pre-migration implementation is retained only in
`compatibility/python-reference` as historical evidence. It is outside the
product build. Its optional replay verifier can be run with a local Python:

```bash
python3 compatibility/python-reference/verify_python_golden.py
```

## Examples

- [`examples/data`](examples/data) contains seven fixed CSV input fixtures.
- [`examples/output`](examples/output) contains the nine reviewed single-leg
  and itinerary SVG results.
- [`examples/README.md`](examples/README.md) documents the naming convention.

## Repository layout

```text
AeroRouteCore/                   Shared Swift package and contract tests
macos/AeroRoute/                 Xcode 27 SwiftUI project for Apple platforms
compatibility/golden/python/    Immutable reviewed SVG fixtures
compatibility/python-reference/ Archived pre-migration evidence only
examples/data/                   Fixed Flightradar24 CSV inputs
examples/output/                 Representative reviewed SVG files
docs/                            Product and architecture documentation
```

The offline map geometry comes from Natural Earth 1:110m public-domain data.
AeroRoute is released under the [MIT License](LICENSE).
