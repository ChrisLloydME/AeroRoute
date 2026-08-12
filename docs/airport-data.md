# Bundled airport data

AeroRoute ships a read-only SQLite airport catalog so airport lookup and future
coordinate matching work without a network connection. The runtime database is
generated from local OurAirports CSV snapshots; the generator never downloads
data.

## Upstream data and license

- Source: [OurAirports open data](https://ourairports.com/data/)
- Input files: `airports.csv` and `countries.csv`
- License: Public Domain
- Bundled snapshot: inspect the `source_version` value in the database's
  `metadata` table

OurAirports provides no guarantee of accuracy or fitness for use. AeroRoute's
catalog is for route illustration and metadata assistance, not operational
flight planning.

## Selection rule

The generated catalog excludes closed airports and retains an open facility if
at least one of these conditions is true:

- it has an IATA code;
- it reports scheduled service; or
- it is classified as a medium or large airport.

This keeps the application resource compact while retaining airports relevant
to airline routes and ICAO-only scheduled destinations. The generator rejects
invalid coordinates, missing countries, malformed IATA/ICAO codes, and duplicate
codes instead of silently producing ambiguous lookup data.

## Updating the bundled database

Downloading is deliberately a separate maintenance action. Obtain a reviewed
`airports.csv` and `countries.csv` snapshot, then run:

```bash
python3 tools/build_airport_database.py \
  --airports /path/to/airports.csv \
  --countries /path/to/countries.csv \
  --output AeroRouteCore/Sources/AeroRouteCore/Resources/airports.sqlite \
  --source-version YYYY-MM-DD
```

The builder uses only the Python standard library. It writes atomically and
runs SQLite's integrity check before replacing the bundled database. It does
not require Python in the shipping application.

Run the generator and bundled-data tests afterward:

```bash
python3 -m unittest discover -s tools/tests -v
swift test --package-path AeroRouteCore
```

Review the recorded provenance and representative airport entries with:

```bash
sqlite3 AeroRouteCore/Sources/AeroRouteCore/Resources/airports.sqlite \
  'SELECT key, value FROM metadata ORDER BY key;'

sqlite3 AeroRouteCore/Sources/AeroRouteCore/Resources/airports.sqlite \
  "SELECT iata_code, icao_code, name FROM airports WHERE iata_code IN ('PVG', 'LHR', 'JFK') ORDER BY iata_code;"
```

Commit the generator change separately if its schema or selection logic changes.
For a routine data refresh, the generated SQLite resource and its reviewed
snapshot metadata are the expected changes.
