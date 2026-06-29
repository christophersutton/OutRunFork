#!/usr/bin/env bash
#
# Build, install, launch, and verify Move: Feet on a paired physical iPhone.
#
# Defaults are tuned for Chris's paired phone:
#   device name: 15
#   Xcode device id: 00008140-001809180C93001C
#   CoreDevice id: BED61CC7-21C4-5023-B681-06E810C54492
#
# Override the target with --device or MOVEFEET_DEVICE when needed.
set -euo pipefail
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORKSPACE="$ROOT_DIR/MoveFeet.xcworkspace"
SCHEME="${MOVEFEET_SCHEME:-MoveFeet}"
CONFIGURATION="${MOVEFEET_CONFIGURATION:-Debug}"
BUNDLE_ID="${MOVEFEET_BUNDLE_ID:-com.wcc.movefeet}"
if [ -n "${MOVEFEET_DEVICE+x}" ]; then
  DEVICE_QUERY="$MOVEFEET_DEVICE"
  DEVICE_QUERY_WAS_DEFAULT=0
else
  DEVICE_QUERY="15"
  DEVICE_QUERY_WAS_DEFAULT=1
fi
DERIVED_DATA_PATH="${MOVEFEET_DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-device}"
ARTIFACT_DIR="${MOVEFEET_DEVICE_ARTIFACT_DIR:-$ROOT_DIR/build/device-install}"
APP_PATH="${MOVEFEET_APP_PATH:-}"
ALLOW_PROVISIONING_UPDATES="${MOVEFEET_ALLOW_PROVISIONING_UPDATES:-1}"

SKIP_BUILD=0
BUILD_ONLY=0
NO_LAUNCH=0
NO_VERIFY=0
LIST_DEVICES=0
VERBOSE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/install-movefeet.sh [options]

Builds Move: Feet from MoveFeet.xcworkspace, installs it on a paired physical
iPhone, launches com.wcc.movefeet, and verifies the running process.

Options:
  --device <name|udid|coredevice-id>
      Device selector. Defaults to MOVEFEET_DEVICE, then "15".
  --app-path <path>
      Install an existing MoveFeet.app and skip the build.
  --skip-build
      Reuse build/DerivedData-device/Build/Products/Debug-iphoneos/MoveFeet.app.
  --build-only
      Build the device app and stop before install.
  --no-launch
      Install the app but do not launch it.
  --no-verify
      Do not check the process list after launch.
  --list-devices
      Print physical iOS devices visible to devicectl and exit.
  --verbose
      Show full xcodebuild output instead of -quiet output.
  -h, --help
      Show this help.

Environment:
  MOVEFEET_DEVICE                    Default device selector; default: 15
  MOVEFEET_CONFIGURATION             Xcode configuration; default: Debug
  MOVEFEET_DERIVED_DATA_PATH         Default: build/DerivedData-device
  MOVEFEET_DEVICE_ARTIFACT_DIR       Default: build/device-install
  MOVEFEET_ALLOW_PROVISIONING_UPDATES Set to 0 to omit -allowProvisioningUpdates

Recovery:
  If install succeeds but launch fails because the phone is locked, unlock it
  and rerun:
    scripts/install-movefeet.sh --skip-build
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      [ "$#" -ge 2 ] || die "--device requires a value"
      DEVICE_QUERY="$2"
      DEVICE_QUERY_WAS_DEFAULT=0
      shift 2
      ;;
    --device=*)
      DEVICE_QUERY="${1#*=}"
      DEVICE_QUERY_WAS_DEFAULT=0
      shift
      ;;
    --app-path)
      [ "$#" -ge 2 ] || die "--app-path requires a value"
      APP_PATH="$2"
      SKIP_BUILD=1
      shift 2
      ;;
    --app-path=*)
      APP_PATH="${1#*=}"
      SKIP_BUILD=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --build-only)
      BUILD_ONLY=1
      shift
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --no-verify)
      NO_VERIFY=1
      shift
      ;;
    --list-devices)
      LIST_DEVICES=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

mkdir -p "$ARTIFACT_DIR"

DEVICES_JSON="$ARTIFACT_DIR/devices.json"
SELECTED_DEVICE_TSV="$ARTIFACT_DIR/selected-device.tsv"
DESTINATIONS_LOG="$ARTIFACT_DIR/destinations.txt"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild-device.log"
INSTALL_JSON="$ARTIFACT_DIR/install.json"
LAUNCH_JSON="$ARTIFACT_DIR/launch.json"
PROCESSES_JSON="$ARTIFACT_DIR/processes.json"

log "Detecting paired physical iOS devices"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

print_devices() {
  python3 - "$DEVICES_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

devices = data.get("result", {}).get("devices", [])
rows = []
for dev in devices:
    hardware = dev.get("hardwareProperties", {})
    props = dev.get("deviceProperties", {})
    connection = dev.get("connectionProperties", {})
    if hardware.get("platform") != "iOS" or hardware.get("reality") != "physical":
        continue
    rows.append(
        (
            props.get("name") or "",
            hardware.get("marketingName") or "",
            hardware.get("udid") or "",
            dev.get("identifier") or "",
            connection.get("pairingState") or "",
            connection.get("tunnelState") or "",
        )
    )

if not rows:
    print("No physical iOS devices visible to devicectl.")
    sys.exit(0)

print("Name\tModel\tXcode device id\tCoreDevice id\tPairing\tTunnel")
for row in rows:
    print("\t".join(row))
PY
}

if [ "$LIST_DEVICES" -eq 1 ]; then
  print_devices
  exit 0
fi

python3 - "$DEVICES_JSON" "$DEVICE_QUERY" "$DEVICE_QUERY_WAS_DEFAULT" >"$SELECTED_DEVICE_TSV" <<'PY'
import json
import sys

json_path, query, default_flag = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
with open(json_path, encoding="utf-8") as handle:
    data = json.load(handle)

devices = data.get("result", {}).get("devices", [])
eligible = []
for dev in devices:
    hardware = dev.get("hardwareProperties", {})
    props = dev.get("deviceProperties", {})
    connection = dev.get("connectionProperties", {})
    if hardware.get("platform") != "iOS" or hardware.get("reality") != "physical":
        continue
    if connection.get("pairingState") != "paired":
        continue
    identifier = dev.get("identifier") or ""
    udid = hardware.get("udid") or ""
    name = props.get("name") or ""
    model = hardware.get("marketingName") or hardware.get("productType") or "iPhone"
    hostnames = connection.get("potentialHostnames") or []
    if identifier and udid:
        eligible.append((identifier, udid, name, model, hostnames))

def matches(row):
    identifier, udid, name, _model, hostnames = row
    return query in {identifier, udid, name} or query in hostnames

selected = [row for row in eligible if matches(row)]
if not selected and default_flag and len(eligible) == 1:
    selected = eligible

if not selected:
    print(f"No paired physical iOS device matched {query!r}.", file=sys.stderr)
    if eligible:
        print("Visible devices:", file=sys.stderr)
        for _identifier, udid, name, model, _hostnames in eligible:
            print(f"  {name} ({model}) {udid}", file=sys.stderr)
    sys.exit(2)

if len(selected) > 1:
    print(f"Device selector {query!r} matched multiple devices.", file=sys.stderr)
    sys.exit(2)

identifier, udid, name, model, _hostnames = selected[0]
print("\t".join([identifier, udid, name, model]))
PY
IFS=$'\t' read -r DEVICECTL_ID XCODE_DEVICE_ID DEVICE_NAME DEVICE_MODEL <"$SELECTED_DEVICE_TSV"

[ -n "${DEVICECTL_ID:-}" ] || die "No paired physical iOS device selected."

log "Using device: $DEVICE_NAME ($DEVICE_MODEL)"
echo "    Xcode destination id: $XCODE_DEVICE_ID"
echo "    CoreDevice id: $DEVICECTL_ID"

log "Checking Xcode destination"
xcodebuild -showdestinations -workspace "$WORKSPACE" -scheme "$SCHEME" >"$DESTINATIONS_LOG"
if ! grep -Fq "id:$XCODE_DEVICE_ID" "$DESTINATIONS_LOG"; then
  die "Xcode does not currently list $DEVICE_NAME ($XCODE_DEVICE_ID) as a destination. See $DESTINATIONS_LOG."
fi

if [ -z "$APP_PATH" ]; then
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/MoveFeet.app"
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  log "Building $SCHEME $CONFIGURATION for physical device"
  rm -f "$BUILD_LOG"

  quiet_args=()
  if [ "$VERBOSE" -eq 0 ]; then
    quiet_args=(-quiet)
  fi

  provisioning_args=()
  if [ "$ALLOW_PROVISIONING_UPDATES" != "0" ]; then
    provisioning_args=(-allowProvisioningUpdates)
  fi

  xcodebuild "${quiet_args[@]}" \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS,id=$XCODE_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${provisioning_args[@]}" \
    build 2>&1 | tee "$BUILD_LOG"
else
  log "Skipping build; using existing app bundle"
fi

[ -d "$APP_PATH" ] || die "MoveFeet.app not found at $APP_PATH"
[ -f "$APP_PATH/Info.plist" ] || die "Info.plist not found inside $APP_PATH"

actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")
if [ "$actual_bundle_id" != "$BUNDLE_ID" ]; then
  die "Built app bundle id is $actual_bundle_id, expected $BUNDLE_ID"
fi

echo "    App bundle: $APP_PATH"
echo "    Bundle id: $actual_bundle_id"
echo "    Artifacts: $ARTIFACT_DIR"

if [ "$BUILD_ONLY" -eq 1 ]; then
  log "Build-only mode complete"
  exit 0
fi

log "Installing on $DEVICE_NAME"
xcrun devicectl device install app \
  --device "$DEVICECTL_ID" \
  "$APP_PATH" \
  --json-output "$INSTALL_JSON"

if [ "$NO_LAUNCH" -eq 1 ]; then
  log "Install complete; launch skipped"
  exit 0
fi

log "Launching $BUNDLE_ID"
if ! xcrun devicectl device process launch \
  --device "$DEVICECTL_ID" \
  --terminate-existing \
  "$BUNDLE_ID" \
  --json-output "$LAUNCH_JSON"; then
  die "Launch failed. If the install succeeded, unlock the phone and rerun scripts/install-movefeet.sh --skip-build"
fi

launch_pid=$(python3 - "$LAUNCH_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("result", {}).get("process", {}).get("processIdentifier", ""))
PY
)
echo "    Launch pid: ${launch_pid:-unknown}"

if [ "$NO_VERIFY" -eq 1 ]; then
  log "Launch complete; process verification skipped"
  exit 0
fi

log "Verifying running process"
sleep 1
xcrun devicectl device info processes \
  --device "$DEVICECTL_ID" \
  --json-output "$PROCESSES_JSON" >/dev/null

python3 - "$PROCESSES_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

processes = data.get("result", {}).get("runningProcesses", [])
app = []
extensions = []
for process in processes:
    executable = str(process.get("executable") or "")
    pid = process.get("processIdentifier")
    if "/MoveFeet.app/MoveFeet" in executable and "/PlugIns/" not in executable:
        app.append((pid, executable))
    if "/MoveFeet.app/PlugIns/MoveFeetActivities.appex/" in executable:
        extensions.append((pid, executable))

if not app:
    print("MoveFeet launch returned successfully, but no running app process was found.", file=sys.stderr)
    sys.exit(1)

print(f"    Verified app pid: {app[0][0]}")
if extensions:
    print(f"    Live Activity extension pid: {extensions[0][0]}")
PY

log "Move: Feet installed and running on $DEVICE_NAME"
