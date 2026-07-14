# -*- mode: python ; coding: utf-8 -*-

import os

target_arch = os.environ.get("AEROROUTE_TARGET_ARCH", "universal2")

a = Analysis(
    ["aeroroute_app.py"],
    pathex=[],
    binaries=[],
    datas=[("aeroroute/data", "aeroroute/data")],
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
    icon=None,
    bundle_identifier="com.aeroroute.app",
    info_plist={
        "CFBundleDisplayName": "AeroRoute",
        "CFBundleShortVersionString": "0.2.0",
        "CFBundleVersion": "2",
        "LSMinimumSystemVersion": "13.0",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "AeroRoute",
    },
)
