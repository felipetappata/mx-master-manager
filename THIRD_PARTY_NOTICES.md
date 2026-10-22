# Third-party notices

MX Master Manager is a focused derivative of
[AprilNEA/OpenLogi](https://github.com/AprilNEA/OpenLogi), based on commit
`6f1299c5c2a7d963dab44d4459da07902340a136`. The original Git history is retained.
Its MIT and Apache-2.0 license texts are preserved in LICENSE-MIT and
LICENSE-APACHE.

The Swift HID++ layer translates the original feature-discovery, adjustable-DPI,
SmartShift, thumbwheel, and reprogrammable-control packet layouts. OpenLogi's
`openlogi-hidpp` crate is based on Lukas Schulte Pelkum's `hidpp` crate and uses
the following license:

```text
BSD Zero Clause License

Copyright (c) 2025 Lukas Schulte Pelkum

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```

Undocumented Core Graphics gesture field numbers were verified against
[Hammerspoon TouchEvents.h](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.h)
and [TouchEvents.c](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.c).
The Swift state machine and event validation are implemented in this fork.

The icon master (`Resources/AppIcon.png`) is a dithered transformation of the MX Master 3 product render, made with the built-in ImageGen tool. `scripts/make-icon.swift` packages the bundled master image at macOS icon sizes. On Xcode 26 or later, the build also compiles an Icon Composer catalog with an opaque near-black purple background and no glass treatment.
OpenLogi's proprietary brand assets are not redistributed.

`Resources/MXMaster3.png` is the Logitech MX Master 3 product render from the
existing local OpenLogi device-asset cache (`mx_master_3/side_core.png`). It is
bundled for offline device identification. Product artwork belongs to its
respective owner and is not covered by this repository's software licenses.

---

*This document was written partially or entirely by AI.*
