# AeroRoute native product architecture

## Product model

AeroRoute is an offline document-style utility: import ordered flight tracks,
review continuity, edit presentation settings, preview the exact renderer, and
export SVG. It is not a live map browser and has no account, network, telemetry,
or background-service layer.

## Shared core

`AeroRouteCore` is the only implementation of the data pipeline used by the
macOS, iPhone, and iPad app:

- `RFC4180CSV` preserves quoting, embedded newlines, optional blanks, and stable
  row semantics from the fixed input contract.
- `FR24` validates coordinates, sorts timestamps stably, and derives filename
  metadata.
- `Geometry` and `GeoJSON` provide the fixed equirectangular projection,
  antimeridian continuity, endpoint distance, itinerary merging, and bundled
  Natural Earth geometry.
- `SVGRenderer` and `XMLNode` preserve the reviewed SVG structure, layer order,
  numeric formatting, paths, labels, colors, canvas, and scale semantics.

The package has no dependency on SwiftUI or an application lifecycle.

## Application state and concurrency

Each window owns one `RouteWorkspace`; windows do not share imported legs,
settings, file panels, or background tasks. CSV reading is serialized off the
main actor while security-scoped access covers identity lookup and file reads.
Preview and export rendering share a serial worker so rapid edits cannot create
overlapping full-map renders.

Workspace revisions make rendering latest-wins. Editing settings, reordering,
removing, or clearing legs cancels and invalidates an older export snapshot, so
the save panel cannot silently present SVG from stale state. Clearing also
resets import, render, export, preview, validation, and selection state.

## Native interaction model

The interface is built from SwiftUI and Apple frameworks:

- `NavigationSplitView`, `List`, and native selection/reordering for flight
  legs.
- A native `Table` for continuity review on wider layouts and a touch-friendly
  list on compact iPhone layouts.
- Standard toolbar commands, menus, shortcuts, drag and drop, `fileImporter`,
  and `fileExporter`.
- A grouped inspector `Form` using `TextField`, `Toggle`, `Stepper`, and
  `ColorPicker`.
- AppKit decodes SVG into `NSImage` for the macOS preview. iPhone and iPad use
  WebKit with JavaScript disabled as their system SVG preview surface. Neither
  path is a web application shell or duplicates rendering logic.

SwiftUI supplies the current operating system's materials, typography,
appearance, focus, safe areas, accessibility semantics, and adaptive behavior.
The app does not manually imitate a newer macOS visual style.

## Platform adaptation

macOS presents an editor window with sidebar, resizable preview/table detail,
inspector, menus, keyboard shortcuts, pointer-friendly controls, file panels,
and file drop. iPad uses the same multi-column information architecture when
space permits. Compact iPhone layouts switch between the map and leg review via
a native segmented picker; the inspector adapts to a system presentation.

The shared Xcode target declares iPhone and iPad device families. iOS and
iPadOS use the same core capabilities rather than placeholder or compile-only
implementations.

## Compatibility and packaging

Nine immutable Python-generated SVG fixtures lock the historical output. Swift
tests compare every result byte-for-byte and separately cover parsing,
metadata, geometry, continuity, GeoJSON, layer composition, serialization, and
file writing.

The product consists of the Xcode application and `AeroRouteCore`. It neither
invokes nor embeds Python, PySide6, Qt, or PyInstaller. The archived Python tree
under `compatibility/python-reference` exists only to preserve provenance and
is not referenced by the Xcode project or Swift package.
