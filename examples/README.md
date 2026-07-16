# Examples

`data/` contains seven fixed Flightradar24 CSV tracks used by the Swift contract
tests. Filenames use lowercase flight numbers without provider download IDs:

```text
data/lx188.csv
output/flight-lx188.svg
```

`output/` contains nine representative SVGs: seven single-flight maps and two
multi-leg itineraries. These files are exact copies of the immutable reviewed
fixtures in `compatibility/golden/python`; update neither location merely to
make a compatibility test pass.

To inspect an example in the native app, open the Xcode project, run the shared
`AeroRoute` scheme, and import one or more CSV files from `data/` in itinerary
order.
