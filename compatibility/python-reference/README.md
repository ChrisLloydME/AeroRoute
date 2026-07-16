# Archived Python reference

This directory preserves the pre-migration Python implementation, its tests,
and its packaging scripts solely as compatibility evidence. It is not part of
the AeroRoute product build and is not required to build or run the native
Apple applications.

The immutable SVG fixtures remain in `../golden/python`. Their manifest records
the original repository paths and commands, so those historical strings are
intentionally unchanged.

To replay the historical renderer against the immutable fixtures from the
repository root:

```bash
python3 compatibility/python-reference/verify_python_golden.py
```

The verifier writes only to a temporary directory and cannot capture or replace
the committed golden files. The shipping Swift app does not invoke this code,
embed Python, or depend on PySide6 or PyInstaller.
