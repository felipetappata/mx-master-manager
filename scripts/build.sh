#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "MX Master Manager requires macOS 13 or later." >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$root/.build"
app="$root/dist/MX Master Manager.app"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$root/dist"

xcrun swift build --package-path "$root" --scratch-path "$build_dir" \
    -c release --product MXMasterManager
bin_dir="$(xcrun swift build --package-path "$root" --scratch-path "$build_dir" \
    -c release --show-bin-path)"

# Staging keeps an existing, usable bundle intact if compiling or drawing fails.
stage="$(mktemp -d "$root/dist/.mx-master-manager.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
staged_app="$stage/MX Master Manager.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$bin_dir/MXMasterManager" "$staged_app/Contents/MacOS/MXMasterManager"
cp "$root/packaging/macos/Info.plist" "$staged_app/Contents/Info.plist"
cp "$root/Resources/MXMaster3.png" "$staged_app/Contents/Resources/"
cp "$root/LICENSE-MIT" "$root/LICENSE-APACHE" "$root/THIRD_PARTY_NOTICES.md" \
    "$staged_app/Contents/Resources/"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"

xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    "$root/scripts/make-icon.swift" "$root/Resources/AppIcon.png" "$stage/AppIcon.iconset"
/usr/bin/iconutil -c icns "$stage/AppIcon.iconset" \
    -o "$staged_app/Contents/Resources/MXMasterDithered.icns"
# Modern macOS wraps legacy transparent icons in a pale system tile. A native
# catalog supplies the intended opaque purple background; older Xcode/macOS
# versions retain the ICNS generated above.
xcode_major="$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { split($2, v, "."); print v[1]; exit }')" || xcode_major=0
if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= 26 )); then
    cp -RL "$root/Resources/MXMasterDithered.icon" "$stage/MXMasterDithered.icon"
    mkdir -p "$stage/catalog"
    xcrun actool "$stage/MXMasterDithered.icon" --compile "$stage/catalog" \
        --app-icon MXMasterDithered --include-all-app-icons --platform macosx \
        --target-device mac --minimum-deployment-target 13.0 \
        --output-partial-info-plist "$stage/catalog/icons.plist"
    cp "$stage/catalog/Assets.car" "$stage/catalog/MXMasterDithered.icns" \
        "$staged_app/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string MXMasterDithered" \
        "$staged_app/Contents/Info.plist"
fi
/usr/bin/plutil -lint "$staged_app/Contents/Info.plist"

# IOHID and CGEvent are used directly. No sandbox or restricted virtual-HID
# entitlement is claimed, and there is no helper process to sign separately.
identity="${CODE_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    echo "Signing ad hoc. Set CODE_SIGN_IDENTITY to a stable Apple Development identity"
    echo "to preserve macOS Input Monitoring and Accessibility grants across rebuilds."
    /usr/bin/codesign --force --sign - --timestamp=none "$staged_app"
else
    echo "Signing with configured identity: $identity"
    /usr/bin/codesign --force --sign "$identity" --options runtime \
        --timestamp=none "$staged_app"
fi
/usr/bin/codesign --verify --strict --verbose=2 "$staged_app"

rm -rf "$app"
mv "$staged_app" "$app"
echo "Built: $app"
echo "Architecture: $(/usr/bin/lipo -archs "$app/Contents/MacOS/MXMasterManager")"
