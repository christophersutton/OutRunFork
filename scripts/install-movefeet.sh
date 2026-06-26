#!/usr/bin/env bash
#
# install-movefeet.sh — build "Move: Feet" (com.wcc.movefeet) for a connected iPhone,
# install it, and launch it. One command to rebuild/reinstall on your device.
#
# Prerequisites (one-time):
#   • Your Apple ID (team W67CF9C739) signed into Xcode ▸ Settings ▸ Accounts.
#   • iPhone plugged in (or paired over Wi-Fi), trusted, with Developer Mode enabled.
#   • The latest Apple Developer Program License Agreement accepted at developer.apple.com.
#
# The project's app target is already configured with the new bundle id + your team, so no
# build-setting overrides are needed (a global override would leak the bundle id into the
# CocoaPods frameworks and fail install with "DuplicateIdentifier").
#
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.wcc.movefeet"
DEVICE_JSON="/tmp/.movefeet-devices.json"

echo "▸ Detecting connected device…"
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1 || {
  echo "✗ devicectl could not list devices."; exit 1; }

read -r DEVICE_ID DEVICE_UDID DEVICE_NAME < <(python3 - "$DEVICE_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
devices = data.get("result", {}).get("devices", [])
def score(dev):
    state = dev.get("connectionProperties", {}).get("tunnelState", "")
    return 0 if state in ("connected", "available") else 1
for dev in sorted(devices, key=score):
    ident = dev.get("identifier", "")
    udid = dev.get("hardwareProperties", {}).get("udid", "")
    name = dev.get("deviceProperties", {}).get("name") or "device"
    if ident and udid:
        print(ident, udid, name)
        break
PY
)

if [ -z "${DEVICE_ID:-}" ]; then
  echo "✗ No connected iPhone found. Plug it in, trust this Mac, and enable Developer Mode."
  exit 1
fi
echo "  → ${DEVICE_NAME} (${DEVICE_UDID})"

echo "▸ Building for device (signing with your team, provisioning auto-updated)…"
xcodebuild -quiet -workspace MoveFeet.xcworkspace -scheme MoveFeet -configuration Debug \
  -destination "platform=iOS,id=${DEVICE_UDID}" \
  -allowProvisioningUpdates \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphoneos/MoveFeet.app" -maxdepth 6 -type d 2>/dev/null \
      | xargs -I{} stat -f '%m %N' {} | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
  echo "✗ Could not locate the built MoveFeet.app (Debug-iphoneos)."; exit 1
fi

echo "▸ Installing ${APP##*/} …"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▸ Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || true

echo "✓ Move: Feet (${BUNDLE_ID}) installed on ${DEVICE_NAME}."
