#!/bin/bash
# Archive a Release build and upload it to App Store Connect (TestFlight).
# Needs: the app to exist in App Store Connect, Xcode signed in to the team,
# and ios/Secrets.xcconfig pointing at the production backend.
#
#   ./testflight-upload.sh            # uses the current version/build in project.yml
#   BUILD=2 ./testflight-upload.sh    # override the build number for this upload
set -euo pipefail
cd "$(dirname "$0")"

OUT="${TMPDIR:-/tmp}/fin4u-release"
rm -rf "$OUT" && mkdir -p "$OUT"

EXTRA=()
if [ -n "${BUILD:-}" ]; then EXTRA+=(CURRENT_PROJECT_VERSION="$BUILD"); fi

xcodegen generate >/dev/null
xcodebuild archive -project Fin4U.xcodeproj -scheme Fin4U -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Fin4U.xcarchive" \
  -allowProvisioningUpdates "${EXTRA[@]}"

xcodebuild -exportArchive -archivePath "$OUT/Fin4U.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates

echo "Uploaded. It shows up in App Store Connect > TestFlight after processing (a few minutes)."
