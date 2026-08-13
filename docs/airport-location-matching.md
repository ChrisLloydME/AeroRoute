# Airport location matching

`AirportSearchEngine` can match the bundled airport catalog from a coordinate,
an ordered ADS-B track, or every endpoint in a combined multi-leg track. The
API is offline, deterministic, and returns candidates even when it declines to
fill a value automatically.

## Matching policy

The matcher uses exact WGS84 great-circle distance. Scanning the roughly ten
thousand bundled airports is intentionally preferred to a spatial tree at the
current catalog size: it keeps the implementation and update pipeline simple,
while a warm query remains fast enough for import-time matching. A spatial
index can be introduced behind the same API if the catalog or workload grows.

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

Otherwise the response is `.manualSelection` and retains the ranked candidates
for user correction. Invalid coordinates and a valid coordinate with no airport
inside the search radius are distinct states.

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
minutes. This resists a noisy individual coordinate while keeping cost bounded.
The values are configurable through `AirportTrackMatchOptions`.

For a multi-leg track created by `combineTracks`:

```swift
let response = engine.matchAirportWaypoints(for: itinerary)

if let airports = response.automaticAirports {
    // Every waypoint was decisive and airports preserve route order.
} else {
    // Inspect each waypoint.response independently; only ambiguous entries
    // need user intervention.
}
```

The stable location-matching types are:

| Type | Purpose |
| --- | --- |
| `AirportCoordinate` | Validated latitude and longitude value |
| `AirportProximityRequest` | Coordinate, result limit, radius, and service preference |
| `AirportProximityCandidate` | Airport, physical distances, support count, confidence |
| `AirportProximityResponse` | Ranked candidates and automatic/manual resolution |
| `AirportTrackMatchOptions` | Track evidence and proximity policy knobs |
| `AirportTrackMatchResponse` | Origin and destination responses for one flight |
| `AirportItineraryMatchResponse` | Ordered responses for all retained waypoints |

## Regression coverage

`AirportLocationMatchTests` verifies invalid and remote coordinates, exact
coordinate lookup, an intentionally ambiguous midpoint, all seven bundled
Flightradar24 examples, and a combined four-airport itinerary. The example
tracks currently resolve as:

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
