# Regression fixtures

`data/` contains seven fixed Flightradar24 CSV tracks used by the Swift core,
application, and UI tests. Filenames use lowercase flight numbers without
provider download IDs, such as `data/lx188.csv`.

`output/` contains nine immutable SVG baselines: seven single-flight maps and
two multi-leg itineraries. `GoldenCompatibilityTests` compares the Swift
renderer's results byte-for-byte and checks the original SHA-256 hashes. Do not
update these files merely to make a test pass.

`output/manifest.json` preserves the original Python renderer's capture metadata,
including source revision, options, commands, and hashes. The paths and commands
in that manifest refer to the historical capture environment. The old renderer
and its packaging scripts are available on the archive branch
`codex/archive-before-native-cleanup-2026-11-05`.

To inspect a fixture in the native app, import a CSV from `data/`. The CSVs and
SVG baselines are test data and are not bundled in AeroRoute.app.
