# Airport search algorithm

`AirportSearchEngine` is an offline, UI-independent search component backed by
the immutable bundled airport database. A caller supplies any Swift `String`
and receives a deterministic, relevance-ranked list of `AirportSearchResult`
values. Empty input, symbols, flags, and emoji are valid and safely return no
results when they contain no searchable text.

## Query processing

The engine processes input in this order:

1. Apply Foundation's best-effort transliteration to Latin script.
2. Fold case, diacritics, and full-width characters using a fixed POSIX locale.
3. Replace punctuation, symbols, and emoji with token boundaries.
4. Collapse whitespace and split the remaining text into terms.
5. Treat a single three- or four-letter ASCII term as a possible airport code.

For example, `✈️ＰＶＧ🛬` becomes the code `PVG`, `São—Paulo` becomes the terms
`sao paulo`, and Chinese `上海` becomes `shang hai` on Apple platforms.
Transliteration is useful but not a multilingual alias database: names whose
common English form differs from their phonetic transliteration may still need
an airport or city alias dataset in the future.

## Recall and ranking

Every retained airport is eligible. The engine scores independent evidence and
then applies stable tie-breakers. Strong signals are deliberately separated
from weaker signals:

1. exact IATA or ICAO code;
2. exact airport name or city;
3. airport-name or city prefix;
4. all query terms found across name, city, country, country code, codes, and
   upstream keywords;
5. bounded edit-distance recovery for a code, airport-name word, or city word.

Small bonuses prefer airports with scheduled service, an IATA code, and a large
or medium classification. These bonuses never outrank a stronger match class.
Remaining ties use airport importance, name, and stable OurAirports ID so the
same database and query always produce the same order.

Fuzzy matching permits one edit for words of four through seven characters and
two edits for longer words. Terms shorter than four characters must match
exactly or by prefix, except for the explicit airport-code recovery path. This
prevents short arbitrary input from producing excessively broad typo matches.

## API

```swift
let search = try AirportSearchEngine()
let results = search.search("Shanghai CN", limit: 10)

for result in results {
    print(result.airport.iataCode ?? "—", result.score, result.reasons)
}
```

Loading can fail if the database resource is unavailable or invalid, so engine
initialization throws. Searching an initialized engine is synchronous,
side-effect free, thread-safe, and performs no network access.
