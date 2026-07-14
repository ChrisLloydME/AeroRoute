# Examples

`data/` contains sample Flightradar24 CSV flight tracks used by the test suite
and the commands in the main README. `output/` contains representative SVG maps
rendered from those tracks.

To render an example locally:

```bash
python3 -m aeroroute examples/data/LX188_40a4c777.csv --output LX188.svg
```

Generated macOS applications and release archives are not examples. The build
scripts place those artifacts in the ignored `dist/` directory.
