# AeroRoute for macOS

## 1. Product context

AeroRoute turns one or more standard Flightradar24 CSV exports into a static,
editable SVG flight record. The desktop app is an offline batch utility rather
than a map browser. Its primary loop is import, order, inspect, label, preview,
and export.

## 2. Product direction

The interface should feel like a restrained native aviation archive tool. It
uses three stable regions: an ordered flight-leg queue, a large live map
preview, and a compact export inspector. The map remains the visual focus.

## 3. Information architecture

- Left: imported CSV legs, drag ordering, add/remove controls, validation state.
- Center: live SVG preview using the same renderer as final export.
- Right: itinerary labels, visibility options, size, line weight, and colors.
- Bottom: point count, continuity status, and export action.

## 4. Interaction model

CSV files may be dropped anywhere on the window or selected with a file dialog.
Multi-leg files are connected only in their displayed order. Reordering updates
the preview and endpoint-distance validation immediately. Export is disabled
when parsing fails or adjacent endpoints are too far apart.

## 5. Visual system

The app uses Qt Widgets with the native macOS style and system palette. Only
typographic hierarchy and map color swatches are customized, so controls follow
the current macOS light or dark appearance automatically. The map palette
follows the existing artwork: ocean `#B2BAC3`, land `#D9D9D9`, coastline
`#787C80`, borders `#A9ADB2`, route `#183143`, marker `#E05B45`, and primary
text `#171D21`. No gradients, ornamental cards, or decorative iconography are
used.

## 6. Typography

Interface typography uses the macOS system sans family. Labels and helper copy
are compact, with clear hierarchy from weight and spacing. Exported artwork
continues to use Helvetica Neue fallbacks so SVG files remain portable.

## 7. States and validation

Each leg exposes loading, ready, and invalid states. Adjacent endpoint distance
is reported in kilometres. A 50 km default tolerance accommodates airport
surface sampling while preventing unrelated flights from being silently joined.
An empty state explains the accepted FR24 workflow without blocking file drop.

## 8. Accessibility and resilience

All actions have text labels and keyboard focus. Status is communicated with
copy as well as color. Parsing and rendering run from the canonical pipeline,
so CLI and app output remain equivalent. The app is offline and writes SVG only.

## 9. Packaging

PyInstaller bundles Python, PySide6, Qt SVG support, and Natural Earth map data
into a standalone macOS application. The build skips signing and notarization
as requested. Build scripts support arm64, x86_64, and universal2 targets when
the local Python and native dependencies contain the requested slices.
