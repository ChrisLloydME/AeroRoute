# Airport search algorithm

`AirportSearchEngine` is an English-only, offline, UI-independent search
component backed by the immutable bundled airport database. A caller supplies
any Swift `String` and receives a deterministic, relevance-ranked list of
`AirportSearchResult` values. Empty input, unsupported scripts, symbols, flags,
and emoji are valid and safely return no results when they contain no searchable
English text.

## Query processing

The engine processes input in this order:

1. Fold English case, Latin diacritics, and full-width characters using a fixed
   POSIX locale.
2. Discard non-ASCII scripts and replace punctuation, symbols, and emoji with
   token boundaries.
3. Expand selected airport abbreviations such as `intl` and `apt`.
4. Treat a single three- or four-letter term as a possible airport code.

The parser expects search terms, not conversational sentences. It does not try
to understand requests such as “please find the airport near London”. Generic
terms such as `airport` by themselves return no result.

For example, `✈️ＰＶＧ🛬` becomes the code `PVG`, and `São—Paulo` becomes the
terms `sao paulo`. Chinese `上海` has no English search terms and returns no
result by design.

## Recall and ranking

The engine builds in-memory posting lists over names, cities, countries, codes,
and OurAirports keywords. The term dictionary is kept in lexical order, so a
binary lower-bound lookup can enumerate a prefix range without materializing
every possible prefix during initialization.

Fuzzy recall uses a separate prepared term index. Terms are grouped by UTF-8
length and store normalized bytes plus a compact character-presence mask. A
query runs increasingly expensive, recall-safe filters:

1. possible term lengths;
2. missing-character mask count;
3. a conservative trigram lower bound for longer terms;
4. bounded optimal-string-alignment distance using three reusable rows.

This design borrows [FuzzyMatch](https://github.com/ordo-one/FuzzyMatch)'s
prepared-query and prefilter pipeline while specializing it for the engine's
already normalized English ASCII vocabulary. It borrows
[MiniSearch](https://github.com/lucaong/minisearch)'s term-to-posting structure,
ordered prefix lookup, and inverse-document-frequency ranking. It does not
embed either project or require a JavaScript runtime.

Strong signals are deliberately separated from weaker signals:

1. exact IATA or ICAO code;
2. exact airport name or city;
3. exact upstream English alias or compact spelling;
4. airport-name, city, or alias prefix;
5. name/alias acronym;
6. all meaningful query terms found across name, city, country, country code,
   codes, and upstream keywords, regardless of word order;
7. bounded edit recovery for missing, extra, substituted, or transposed
   characters;
8. compact-field correction for merged words and longer phrase errors.

Exact, prefix, and corrected terms receive a capped inverse-document-frequency
bonus. Distinctive terms such as `heathrow` therefore contribute more than
common terms, without allowing statistical relevance to outrank an exact code
or exact airport identity. Alias-only fuzzy evidence is deliberately weaker
than airport-name and city evidence.

Small bonuses prefer airports with scheduled service, an IATA code, and a large
or medium classification. These bonuses never outrank a stronger match class.
Remaining ties use airport importance, name, and stable OurAirports ID so the
same database and query always produce the same order.

Fuzzy matching permits one edit for words of four through eight characters and
two edits for longer words. Terms shorter than four characters must match
exactly or by prefix. A three- or four-letter code is corrected only when the
input consists of that code alone and no exact code exists. This prevents a real
airport code from being silently replaced by another one.

Results include `.exact`, `.high`, `.medium`, or `.low` confidence. City queries
that plausibly identify several airports mark the near-top candidates as
`isAmbiguous`; exact IATA/ICAO matches are decisive. Consumers should use these
properties instead of automatically accepting the first low-confidence result.

## API

UI code should use the unified request/response API for both phases:

```swift
let search = try AirportSearchEngine()

let response = search.lookup(.init(
    text: currentText,
    phase: isEditing ? .editing : .submitted,
    limit: nil // phase default: 8 while editing, 20 when submitted
))

switch response.resolution {
case .emptyInput:
    // No supported searchable English text.
case .noMatches:
    // Valid search text, but no result met the threshold.
case .suggestions, .manualSelection:
    // Present response.results and let the user select.
case .automaticSelection:
    if let result = response.automaticSelection {
        // It is safe to fill result.airport.
    }
}
```

The stable contract is:

| Type | Purpose |
| --- | --- |
| `AirportSearchRequest` | Original text, `.editing`/`.submitted` phase, optional limit |
| `AirportSearchResponse` | Echoed request, normalized text, resolution, ranked results |
| `AirportSearchResolution` | UI state and automatic/manual-selection decision |
| `AirportSearchResult` | Identifiable airport, confidence, ambiguity, diagnostic reasons |
| `Airport` | Stable ID, country/city/name, IATA/ICAO, coordinates and service metadata |

Only a submitted result with `.exact` confidence and no ambiguity produces
`.automaticSelection`. Editing never automatically selects, even when the
current text happens to equal a code. UI code must not derive behavior from the
raw integer `score`; it is an internal ranking value whose scale may evolve.

`AirportSearchResult.id` is the underlying stable airport ID, so result arrays
can be passed directly to SwiftUI `ForEach`. `Airport` includes both
`countryCode` and `countryName`; the UI does not need a separate country lookup.

`response.request` echoes the complete request. If lookup is dispatched from an
asynchronous UI task, compare the echoed text or the complete request with the
current field state before applying the response.

The older `search(_:limit:)` and `suggestions(for:limit:)` methods remain as
compatibility wrappers and return exactly the same result arrays as `lookup`.

Loading can fail if the database resource is unavailable or invalid, so engine
initialization throws. Build and retain one engine rather than recreating it for
every keystroke: initialization builds the immutable indexes, while subsequent
searches are synchronous, side-effect free, thread-safe, and perform no network
access.

## Search as you type

Use `suggestions(for:limit:)` while a search field is being edited:

```swift
let suggestions = search.suggestions(for: currentText, limit: 8)
```

The suggestion policy differs intentionally from a submitted `search`:

- one character can recall code, name, city, and alias prefixes;
- exact and prefix matches are available immediately;
- fuzzy text matching begins at four characters;
- fuzzy airport-code correction stays disabled while typing;
- one- and two-character inputs cap detailed scoring to 512 important
  candidates while preserving exact code and acronym candidates;
- the default result limit is eight.

This prevents a partially typed real code from being “corrected” to an unrelated
airport. A UI may still debounce view updates, but the engine itself is
synchronous and keeps no mutable query state. Once the user submits the field,
call `search(_:limit:)` to enable the complete fuzzy policy.

## Quality and performance regression set

`AirportSearchQualityTests` keeps representative exact, descriptive, typo,
incremental-prefix, and negative queries executable against the bundled
database. The typo set includes transposition, insertion, deletion,
substitution, multi-term errors, and merged phrases.

`AirportSearchEvaluationTests` complements those hand-picked regressions with
a deterministic corpus selected from every bundled database revision. It
samples up to two scheduled large or medium airports per country, requires a
globally distinctive English term, and uses a stable hash order. Each selected
term is evaluated literally, as an incremental prefix, and with reproducible
deletion, insertion, substitution, and adjacent-transposition errors. Separate
code and nonsense corpora test decisive lookup and false-positive rejection.

The 2026-08-13 bundled database produces 1,019 evaluation queries:

| Evaluation slice | Result |
| --- | ---: |
| 240 exact IATA/ICAO queries | 240/240 Top-1 |
| 120 distinctive English terms | 117/120 Top-1 |
| 475 generated single-edit typos | 440/475 Top-1; 469/475 Top-3 |
| 120 incremental prefixes | 117/120 Top-8 |
| 64 deterministic nonsense strings | 64/64 rejected |

The corpus exposed a failure that the original ten typo regressions did not:
evidence accumulated from several generic prefix fields could outrank an exact
airport code. Ranking now compares semantic match classes lexicographically
before comparing additive relevance scores, so exact codes cannot be displaced
by repeated weaker evidence.

On the same arm64 machine and Release build on 2026-08-13, comparing commit
`4b7e745` with the optimized implementation using the same test cases:

| Workload | Before | After |
| --- | ---: | ---: |
| Engine construction plus 12 exact/descriptive queries | 944 ms | 314 ms |
| 10 representative typo queries after construction | 154 ms | 2 ms |
| 3 incremental Schiphol prefix queries | 48 ms | 1 ms |
| Typo Top-1 accuracy | 8/10 | 10/10 |

These figures are regression evidence rather than cross-device guarantees. Run
the Release quality suite after changing index construction, edit thresholds,
or field weights:

```sh
cd AeroRouteCore
swift test -c release --filter AirportSearchQualityTests
swift test -c release --filter AirportSearchEvaluationTests
```
