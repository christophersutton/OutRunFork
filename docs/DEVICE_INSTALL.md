# Device Install

Use `scripts/install-movefeet.sh` for repeatable physical iPhone builds.

```bash
scripts/install-movefeet.sh
```

The script defaults to Chris's paired phone named `15`. It discovers the current CoreDevice and Xcode identifiers from `xcrun devicectl list devices`, then builds with the Xcode-reported physical-device id.

Current known identifiers for that phone:

- Device name: `15`
- Xcode destination id: `00008140-001809180C93001C`
- CoreDevice id: `BED61CC7-21C4-5023-B681-06E810C54492`

The identifiers can change if the phone is re-paired, so the script discovers them each run. If the device is renamed or another phone should be used:

```bash
scripts/install-movefeet.sh --device "15"
MOVEFEET_DEVICE="15" scripts/install-movefeet.sh
```

## What It Does

1. Lists paired physical iOS devices with `devicectl`.
2. Verifies Xcode exposes the selected phone as a `MoveFeet` scheme destination.
3. Builds `MoveFeet.xcworkspace` / `MoveFeet` / `Debug` for `iphoneos`.
4. Writes build output to `build/DerivedData-device`.
5. Installs `build/DerivedData-device/Build/Products/Debug-iphoneos/MoveFeet.app`.
6. Launches `com.wcc.movefeet` with `--terminate-existing`.
7. Verifies the app process is running on the phone.

Build logs and JSON command proof are written under `build/device-install`, which is ignored by git.

## Useful Commands

```bash
scripts/install-movefeet.sh --list-devices
scripts/install-movefeet.sh --skip-build
scripts/install-movefeet.sh --no-launch
scripts/install-movefeet.sh --build-only
scripts/install-movefeet.sh --verbose
```

Use `--skip-build` after a successful build if installation or launch needs a retry.

Use `--app-path <path>` to install an existing `MoveFeet.app` bundle:

```bash
scripts/install-movefeet.sh --app-path /path/to/MoveFeet.app
```

## Common Recovery

If install fails, check that the phone is awake, trusted, paired, and has Developer Mode enabled:

```bash
xcrun devicectl list devices
```

If install succeeds but launch fails, the phone is usually locked. Unlock it, then rerun:

```bash
scripts/install-movefeet.sh --skip-build
```

If signing fails, confirm the Apple Development account for team `W67CF9C739` is signed into Xcode and that the current Apple Developer Program license agreement has been accepted.
