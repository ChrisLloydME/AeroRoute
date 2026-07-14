# Examples

Example filenames use lowercase flight numbers without provider download IDs:

```text
data/lx188.csv
output/flight-lx188.svg
```

`data/` contains six Flightradar24 CSV tracks used by the test suite and the
commands in the main README. `output/` contains representative SVG maps,
including single-flight and multi-leg renders.

Render an example from the repository root:

```bash
python3 -m aeroroute examples/data/lx188.csv --output lx188.svg
```

Generated applications and release archives are not examples. The macOS build
places those artifacts in the ignored `dist/` directory.
