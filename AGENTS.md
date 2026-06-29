# Agent Notes

## Build Entry Points

- Use `/Users/chrissutton/wavelength/OutRunFork/MoveFeet.xcworkspace`, not the `.xcodeproj`, for app builds. The project path by itself can miss CocoaPods modules such as `CoreStore`, `Cache`, `CombineExt`, `SnapKit`, and `CoreGPX`.
- Main app scheme: `MoveFeet`.
- Main bundle id: `com.wcc.movefeet`.
- Current physical-device script: `scripts/install-movefeet.sh`.

## Simulator Validation

- Prefer XcodeBuildMCP for simulator builds.
- Always call `session_show_defaults` before the first simulator build/test in a session.
- Current XcodeBuildMCP defaults point at:
  - workspace: `/Users/chrissutton/wavelength/OutRunFork/MoveFeet.xcworkspace`
  - scheme: `MoveFeet`
  - simulator: `iPhone 16 Pro`
- Do not pass `-derivedDataPath` through `build_sim` `extraArgs` when the MCP profile already owns build options. Doing so fails with: `option '-derivedDataPath' may only be provided once`.
- A clean simulator build was verified with plain `build_sim` after checking defaults.

## Physical iPhone Install

- Use the repo script for real-device build/install:

```sh
scripts/install-movefeet.sh
```

- List visible paired devices:

```sh
scripts/install-movefeet.sh --list-devices
```

- Current default paired phone:
  - device name: `15`
  - model: `iPhone 16`
  - Xcode destination id: `00008140-001809180C93001C`
  - CoreDevice id: `BED61CC7-21C4-5023-B681-06E810C54492`

- The script builds from `MoveFeet.xcworkspace`, installs the built app with `xcrun devicectl`, launches `com.wcc.movefeet`, and verifies the running process.
- Build output path: `build/DerivedData-device/Build/Products/Debug-iphoneos/MoveFeet.app`.
- Device install artifacts/logs: `build/device-install/`.
- If the app is already built, reinstall without rebuilding:

```sh
scripts/install-movefeet.sh --skip-build
```

- If the goal is only install proof and the phone may be locked, skip launch:

```sh
scripts/install-movefeet.sh --skip-build --no-launch
```

## Known Device Failure Modes

- `xcrun devicectl list devices` is the readiness source of truth. The phone must be `available (paired)` or otherwise visible to `devicectl` before install can work.
- `scripts/install-movefeet.sh --list-devices` may show `Tunnel` as `disconnected` before install. This is not necessarily fatal; `devicectl` can acquire a tunnel during install.
- Install can succeed while launch fails if the phone is locked. The launch failure appears as CoreDevice error `10002` with reason `Locked` / `Unable to launch ... because the device was not, or could not be, unlocked`.
- Recovery after a locked launch failure:

```sh
scripts/install-movefeet.sh --skip-build
```

- Recovery when only install confirmation is needed:

```sh
scripts/install-movefeet.sh --skip-build --no-launch
```

## Delegation Boundary

- Subagents can audit code or implement repo changes, but the main agent should own physical-device build/install/launch verification. Do not ask subagents to run `scripts/install-movefeet.sh` or direct `devicectl` installs.
