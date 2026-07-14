#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

target_arch="${1:-universal2}"
case "$target_arch" in
  universal2|arm64|x86_64) ;;
  *)
    print -u2 "Usage: scripts/build_macos.sh [universal2|arm64|x86_64]"
    exit 2
    ;;
esac

python_bin="${PYTHON_BIN:-python3}"
venv_dir="${VENV_DIR:-.venv-build}"

if [[ ! -x "$venv_dir/bin/python" ]]; then
  "$python_bin" -m venv "$venv_dir"
fi

"$venv_dir/bin/python" -m pip install --upgrade pip
"$venv_dir/bin/python" -m pip install -r requirements-app.txt

export AEROROUTE_TARGET_ARCH="$target_arch"
export PYINSTALLER_CONFIG_DIR="${PWD}/build/.pyinstaller-cache"
"$venv_dir/bin/pyinstaller" --noconfirm --clean AeroRoute.spec

print "Built dist/AeroRoute.app ($target_arch)"
file dist/AeroRoute.app/Contents/MacOS/AeroRoute
