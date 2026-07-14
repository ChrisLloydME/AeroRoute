# -*- mode: python ; coding: utf-8 -*-

import os
import runpy
import subprocess
from pathlib import Path

target_arch = os.environ.get("AEROROUTE_TARGET_ARCH", "universal2")
project_root = Path.cwd()
app_version = runpy.run_path(project_root / "aeroroute" / "_version.py")["__version__"]
icon_source = project_root / "AppIcon.icon"
asset_catalog = project_root / "resources" / "Assets.xcassets"
icon_build_dir = project_root / "build" / "icon-assets"
icon_build_dir.mkdir(parents=True, exist_ok=True)
icon_info_plist = icon_build_dir / "Info.plist"

subprocess.run(
    [
        "xcrun",
        "actool",
        str(asset_catalog),
        str(icon_source),
        "--compile",
        str(icon_build_dir),
        "--platform",
        "macosx",
        "--minimum-deployment-target",
        "13.0",
        "--app-icon",
        "AppIcon",
        "--output-partial-info-plist",
        str(icon_info_plist),
        "--output-format",
        "human-readable-text",
    ],
    check=True,
)

icon_file = icon_build_dir / "AppIcon.icns"
assets_car = icon_build_dir / "Assets.car"

a = Analysis(
    ["aeroroute_app.py"],
    pathex=[],
    binaries=[],
    datas=[
        ("aeroroute/data", "aeroroute/data"),
        (str(assets_car), "."),
    ],
    hiddenimports=["PySide6.QtSvg", "PySide6.QtSvgWidgets"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets"],
    noarchive=False,
    optimize=1,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="AeroRoute",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=target_arch,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="AeroRoute",
)
app = BUNDLE(
    coll,
    name="AeroRoute.app",
    icon=str(icon_file),
    bundle_identifier="com.lloydME.AeroRoute",
    info_plist={
        "CFBundleDisplayName": "AeroRoute",
        "CFBundleIconFile": "AppIcon",
        "CFBundleIconName": "AppIcon",
        "CFBundleShortVersionString": app_version,
        "CFBundleVersion": app_version,
        "LSMinimumSystemVersion": "13.0",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "AeroRoute",
    },
)
