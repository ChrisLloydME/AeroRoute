#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
app="${1:-dist/AeroRoute.app}"
expected_arch="${2:-universal2}"
binary="$app/Contents/MacOS/AeroRoute"

[[ -x "$binary" ]] || { print -u2 "Missing executable: $binary"; exit 1; }

architectures="$(lipo -archs "$binary")"
case "$expected_arch" in
  universal2) required_architectures=(arm64 x86_64) ;;
  arm64|x86_64) required_architectures=("$expected_arch") ;;
  *)
    print -u2 "Usage: scripts/verify_macos_bundle.sh [app] [universal2|arm64|x86_64]"
    exit 2
    ;;
esac

for required in "${required_architectures[@]}"; do
  [[ "$architectures" == *"$required"* ]] || {
    print -u2 "Executable is missing the $required slice"
    exit 1
  }
done

python_framework="$app/Contents/Frameworks/Python.framework/Versions/Current/Python"
qt_framework="$app/Contents/Frameworks/PySide6/Qt/lib/QtCore.framework/Versions/A/QtCore"
for framework in "$python_framework" "$qt_framework"; do
  [[ -f "$framework" ]] || { print -u2 "Missing framework: $framework"; exit 1; }
  framework_architectures="$(lipo -archs "$framework")"
  for required in "${required_architectures[@]}"; do
    [[ "$framework_architectures" == *"$required"* ]] || {
      print -u2 "Framework is missing the $required slice: $framework"
      exit 1
    }
  done
done

print "Verified $expected_arch bundle slices: $architectures"
