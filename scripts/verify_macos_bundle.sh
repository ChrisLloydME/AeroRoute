#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
app="${1:-dist/AeroRoute.app}"
binary="$app/Contents/MacOS/AeroRoute"

[[ -x "$binary" ]] || { print -u2 "Missing executable: $binary"; exit 1; }

architectures="$(lipo -archs "$binary")"
[[ "$architectures" == *arm64* ]] || { print -u2 "Missing arm64 slice"; exit 1; }
[[ "$architectures" == *x86_64* ]] || { print -u2 "Missing x86_64 slice"; exit 1; }

python_framework="$app/Contents/Frameworks/Python.framework/Versions/3.14/Python"
qt_framework="$app/Contents/Frameworks/PySide6/Qt/lib/QtCore.framework/Versions/A/QtCore"
for framework in "$python_framework" "$qt_framework"; do
  framework_architectures="$(lipo -archs "$framework")"
  [[ "$framework_architectures" == *arm64* && "$framework_architectures" == *x86_64* ]] || {
    print -u2 "Framework is not universal2: $framework"
    exit 1
  }
done

print "Verified universal2 bundle slices: $architectures"
