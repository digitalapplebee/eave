#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x dist/Eave.app/Contents/MacOS/Eave ]]; then
    ./Scripts/build-app.sh debug
fi
exec dist/Eave.app/Contents/MacOS/Eave --verify-desktop
