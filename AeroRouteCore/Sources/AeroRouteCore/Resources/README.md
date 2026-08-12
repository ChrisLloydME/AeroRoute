# Map data

`ne_110m_land.geojson` and `ne_110m_admin_0_countries.geojson` come from
[Natural Earth](https://www.naturalearthdata.com/) via the Natural Earth vector
repository. Natural Earth data is in the public domain.

The 1:110m scale is intentionally retained as part of AeroRoute's deterministic
SVG compatibility contract. The files are bundled as Swift Package resources
and are available offline on macOS, iPhone, and iPad.

# Airport data

`airports.sqlite` is a read-only catalog generated from the Public Domain
[OurAirports](https://ourairports.com/data/) `airports.csv` and `countries.csv`
datasets. The database records its exact source version, source-file SHA-256
hashes, filtering rule, schema version, and row counts in its `metadata` table.

The database is generated rather than edited. See
[`docs/airport-data.md`](../../../../docs/airport-data.md) for the update and
validation procedure.
