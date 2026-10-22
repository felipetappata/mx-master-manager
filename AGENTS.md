# MX Master Manager

macOS-only Swift menu bar utility for Felipe's Bluetooth MX Master 3.
The upstream OpenLogi history is retained in Git; its Rust workspace is no
longer part of the runtime or build.

## Architecture

- `Sources/MXMasterManager/HIDTransport.swift`: IOHID transport, bounded HID++ requests.
- `Sources/MXMasterManager/MouseDevice.swift`: device settings and temporary control diversion.
- `Sources/MXMasterManager/InputController.swift`: macOS input synthesis.
- `Sources/MXMasterManager/ButtonAction.swift`: the focused action catalog.
- `Sources/MXMasterCore/`: pure gesture state, with tests under `Tests/`.
- `Sources/MXMasterManager/ManagerModel.swift`: local preferences and permission gating.
- `Sources/MXMasterManager/SettingsView.swift`: native SwiftUI settings.
- `Sources/MXMasterManager/App.swift`: menu bar, window, app lifecycle.
- `scripts/build.sh`: app bundle, original icon, and signing.
- `Resources/MXMaster3.png`: offline mouse render and calibrated hotspots in the view.

Keep device access off the main thread. Only the MX Master 3 Bluetooth
HID++ interface is supported. Do not broaden global input interception to
other mice or the trackpad. Restore borrowed reporting state on orderly quit,
and cancel held gestures on disconnect. Never claim a requested HID++ write
succeeded without checking the reply/readback.

The app owns its Input Monitoring and Accessibility identity directly. Do not
add helper processes or restricted virtual-HID entitlements. Native Smart Zoom
and pinch event construction must fail explicitly if macOS rejects their type.

Use Apple frameworks, local preferences, and no network services. Preserve the
small single-device scope; do not reintroduce an all-Logitech control suite.

## Verification

Run `swift test` for gesture invariants and `./scripts/build.sh` for a release
bundle. Verify the final bundle signature and launch it through LaunchServices.
A successful build does not prove device behavior or a macOS permission grant.
Report hardware checks separately from synthetic tests. Preserve both license
files and the upstream source provenance in README.
