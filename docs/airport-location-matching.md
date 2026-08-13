# Airport location matching

`AirportSearchEngine` can match the bundled airport catalog from a coordinate,
one ordered ADS-B track, or a batch of independently imported CSV files. The
API is offline, deterministic, and returns candidates even when it declines to
fill a value automatically.

## Matching policy

The matcher uses exact WGS84 great-circle distance. It keeps precomputed airport
coordinates in radians and rejects airports outside the query's latitude band
before evaluating the more expensive Haversine expression. Scanning the roughly
ten thousand lightweight records is intentionally preferred to a spatial tree
at the current catalog size; a spatial index can still be introduced behind the
same API if the catalog or workload grows.

Physical distance is the primary signal. The ranker applies only small,
bounded tie-break bonuses:

- up to 0.4 km for repeated endpoint observations within the support radius;
- 0.55 km for scheduled service;
- 0.2 km for an IATA code;
- 0.2 km for a large airport or 0.1 km for a medium airport.

These priors handle colocated operational facilities, such as a commercial
terminal beside an air base, without allowing a well-known airport farther
away to defeat a genuinely closer candidate.

A candidate has high confidence within 5 km, medium confidence within 25 km,
and low confidence beyond 25 km. Automatic selection additionally requires:

1. high confidence;
2. endpoint evidence when the source contains multiple observations; and
3. at least a 2 km adjusted lead over the runner-up, increasing to 75% of the
   endpoint distance when the first candidate is farther away.

The automatic-selection decision always evaluates at least a 25 km ambiguity
horizon and is independent of the caller's visible result `limit`. Requesting
one result, or using a narrow display radius, therefore cannot hide a nearby
runner-up and turn an ambiguous result into an automatic fill.

Otherwise the response is `.manualSelection` and retains the ranked candidates
for user correction. Invalid coordinates, invalid request/options, and a valid
coordinate with no airport inside the search radius are distinct states.

## APIs

For one coordinate:

```swift
let response = engine.airports(near: .init(
    coordinate: .init(latitude: 31.1434, longitude: 121.805),
    limit: 5,
    maximumDistanceKM: 100
))

if let airport = response.automaticSelection?.airport {
    // Safe to fill PVG; otherwise show response.candidates.
}
```

For one flight track:

```swift
let response = engine.matchAirports(for: imported.track)
let origin = response.automaticOrigin?.airport
let destination = response.automaticDestination?.airport
```

The matcher samples at most 64 observations from the first and last ten
minutes. It reads only the relevant prefix and suffix of an ordered track rather
than filtering the entire flight twice. This resists a noisy individual
coordinate while keeping cost bounded. The values are configurable through
`AirportTrackMatchOptions`; non-finite or negative distance/time settings are
rejected as `.invalidRequest` and never produce an automatic selection.

For multiple CSV files:

```swift
let files = engine.matchAirportFiles(importedLegs)

for file in files {
    // file.inputIndex preserves input order.
    // file.source and file.metadata stay bound to the original CSV.
    let origin = file.match.automaticOrigin?.airport
    let destination = file.match.automaticDestination?.airport
}
```

Batch matching never calls `combineTracks`, validates continuity, or shares
endpoint evidence between files. Each CSV is a separate inference unit, so
non-contiguous inputs are valid and cannot affect one another's ranking.

The stable location-matching types are:

| Type | Purpose |
| --- | --- |
| `AirportCoordinate` | Validated latitude and longitude value |
| `AirportProximityRequest` | Coordinate, result limit, radius, and service preference |
| `AirportProximityCandidate` | Airport, physical distances, support count, confidence |
| `AirportProximityResponse` | Ranked candidates and automatic/manual resolution |
| `AirportTrackMatchOptions` | Track evidence and proximity policy knobs |
| `AirportTrackMatchResponse` | Origin and destination responses for one flight |
| `AirportFileMatchResponse` | Input index, original CSV metadata, and that file's match |

## Regression coverage

`AirportLocationMatchTests` and `AirportLocationEdgeCaseTests` verify invalid
and remote coordinates, invalid options, result-limit invariance, hidden nearby
competitors, closed latitude/longitude bounds, the antimeridian, the poles, an
intentionally ambiguous midpoint, all seven bundled Flightradar24 examples,
and a deliberately non-contiguous three-file batch. The example tracks
currently resolve as:

| File | Expected route |
| --- | --- |
| `fi217.csv` | CPH → KEF |
| `lh2440.csv` | MUC → CPH |
| `lh727.csv` | PVG → MUC |
| `lx1279.csv` | CPH → ZRH |
| `lx188.csv` | ZRH → PVG |
| `sk2596.csv` | KEF → CPH |
| `sq22.csv` | SIN → EWR |

`AirportLocationEvaluationTests` rebuilds a deterministic 240-airport sample
from every database revision. It applies an approximately 1 km diagonal
coordinate perturbation to scheduled large and medium airports. With the
2026-08-13 database, results are 240/240 Top-1, 240/240 Top-3, and 240/240
correct automatic selections. This synthetic corpus measures local robustness;
the seven tracks retain separate coverage for real ADS-B endpoint behavior.

Run the focused suite after changing distance thresholds, tie-break priors, or
endpoint evidence handling:

```sh
cd AeroRouteCore
swift test -c release --filter AirportLocationMatchTests
```
