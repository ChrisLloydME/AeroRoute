"""AeroRoute: deterministic SVG maps for ADS-B flight tracks."""

from .model import Track, TrackPoint, combine_tracks, load_track
from .svg import MapStyle, RenderOptions, RenderStats, build_svg, write_svg

__all__ = [
    "MapStyle",
    "RenderOptions",
    "RenderStats",
    "Track",
    "TrackPoint",
    "build_svg",
    "combine_tracks",
    "load_track",
    "write_svg",
]

__version__ = "0.1.0"
