# MX Master Manager

A small native macOS menu bar app for an MX Master 3 connected over Bluetooth.
One Swift process, system frameworks, local preferences. No account, telemetry,
device-image downloads, updater, web view, or Logitech software.

## Controls

| Control | Behavior |
| --- | --- |
| Thumb button tap | macOS Smart Zoom, equivalent to a two-finger double tap |
| Hold thumb button and move forward | Continuous pinch zoom in |
| Hold thumb button and move backward | Continuous pinch zoom out |
| Back / forward buttons | Command-[ / Command-] |
| Thumb wheel | Native horizontal scrolling |
| Main wheel | Native scrolling and mode button; adjustable SmartShift |
| Pointer | Adjustable hardware DPI |

The settings window keeps OpenLogi's device rail, interactive mouse render,
and selected-button inspector. Back, Forward, and the thumb-button tap have
action pickers. The app also includes DPI, SmartShift threshold,
ratchet/free-spin mode, zoom speed, and open at login. The mouse render is
bundled locally, so the app does not fetch assets. Closing the window leaves the menu bar app running.
Quit from the menu bar to restore the button reporting borrowed from the mouse.

## Build and run

Requires macOS 13 or later and Xcode command-line tools with Swift 5.9 or later.

```sh
swift test
./scripts/build.sh
open "dist/MX Master Manager.app"
```

For stable macOS permission grants across rebuilds, set `CODE_SIGN_IDENTITY` to
an installed Apple Development or Developer ID identity when building. Without
it, the script signs ad hoc and new builds may need permission again.

Quit OpenLogi and Logi Options+ before using the app. Grant **MX Master Manager**
Input Monitoring and Accessibility in System Settings, then restart the app.
These grants apply to this app, separately from OpenLogi's agent. The app stays
inactive while a conflicting manager is detected or permission is missing.

## Scope and compatibility

This fork deliberately targets the attached MX Master 3's Bluetooth HID++
interface (Logitech vendor `0x046d`, product `0xb023`). Other MX Master models,
receivers, keyboards, webcams, lights, Flow, action rings, and per-app profiles
are outside this app's current scope. Middle click, left/right click, and normal
scrolling retain their native behavior.

Smart Zoom and pinch injection use undocumented Core Graphics gesture fields,
as in [Hammerspoon's native event implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.c).
The app validates the constructed events with AppKit and reports an error if
macOS stops recognizing them. Each target app decides whether to handle these
gestures. This is content zoom, not Accessibility screen zoom.

## Origin

Forked from [AprilNEA/OpenLogi](https://github.com/AprilNEA/OpenLogi) at
[`6f1299c5`](https://github.com/AprilNEA/OpenLogi/tree/6f1299c5c2a7d963dab44d4459da07902340a136).
The original history remains in Git. The Swift HID++ implementation follows
its feature discovery, DPI, SmartShift, and reprogrammable-control methods,
particularly the original `reprog_controls.rs`, `adjustable_dpi.rs`, and
`smartshift_enhanced.rs` protocol implementations. The original cross-platform
Rust/GPUI suite has been removed from the application tree.

Code retains OpenLogi's MIT / Apache-2.0 licensing; see LICENSE-MIT and
LICENSE-APACHE. The app icon is a deterministic 128-pixel Bayer dither of the original mouse render, enlarged with nearest-neighbor sampling. It uses only white, grey, and near-black purple. Regenerate the bundled master with `python3 scripts/dither-icon.py Resources/MXMaster3.png Resources/AppIcon.png` (requires Pillow).
OpenLogi's proprietary logo and icon are not included.

---

*This README was written partially or entirely by AI.*
