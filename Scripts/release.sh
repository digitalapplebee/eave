#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$eave_root"
eave_parse_distribution_options "$@"
eave_read_version
if [[ "$eave_signed" == true ]]; then
    eave_require_signing_identity
    [[ -n "${NOTARY_PROFILE:-}" ]] || eave_fail 'Signed release requires a valid NOTARY_PROFILE.'
fi
swift test
if [[ "$eave_signed" == true ]]; then "$eave_root/Scripts/build-app.sh" release --signed
else "$eave_root/Scripts/build-app.sh" release; fi
"$eave_root/Scripts/package.sh" "$@"
echo 'Local release preparation finished. Nothing was uploaded to GitHub or published.'
