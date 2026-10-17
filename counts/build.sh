#!/bin/bash
# Builds Counts.app from the SwiftPM package. Xcode has to be installed (the Command Line Tools
# lack SwiftUI's macro plugin), but it never opens.
#
#   ./build.sh           build a release Counts.app (Apple silicon and Intel) into build/
#   ./build.sh debug     build a debug copy instead
#   ./build.sh run       build a debug copy and open it (it appears in the menu bar)
#   ./build.sh install   build a release copy into ~/Applications and open it
#
# Run the tests with `swift test`.
#
# To try syncing without touching iCloud Drive, point a copy at other folders:
#   open -n build/Counts.app --args -CountsSyncFolder /tmp/cloud -CountsLocalFolder /tmp/mac-a
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Counts.app"
WIDGETS="$APP/Contents/PlugIns/CountsWidgets.appex"
ICON="$ROOT/build/AppIcon.icns"
INSTALLED="$HOME/Applications/Counts.app"
ACTION="${1:-release}"

case "$ACTION" in
  release | install) CONFIG=release ;;
  debug | run) CONFIG=debug ;;
  *)
    echo "usage: $0 [release|debug|run|install]" >&2
    exit 1
    ;;
esac

cd "$ROOT"

# The oldest macOS Counts runs on. Package.swift has to agree, since the compiler checks what the
# code calls against its deployment target.
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
PACKAGE_MIN_MACOS="$(swift package dump-package | plutil -extract platforms.0.version raw -o - -)"
if [ "$PACKAGE_MIN_MACOS" != "$MIN_MACOS" ]; then
  echo "Package.swift targets macOS $PACKAGE_MIN_MACOS, but Info.plist says $MIN_MACOS." >&2
  exit 1
fi
SDK="$(xcrun --show-sdk-version)"

# Every product: the app and its widgets.
BUILD=(-c "$CONFIG")
# Release builds also run on Intel Macs.
if [ "$CONFIG" = release ]; then
  BUILD+=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling ($CONFIG)"
swift build "${BUILD[@]}"
BIN="$(swift build "${BUILD[@]}" --show-bin-path)"

# The icon only changes when its script does, so it's drawn again only then.
if [ Tools/MakeIcon.swift -nt "$ICON" ]; then
  echo "==> Drawing icon"
  swift Tools/MakeIcon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o "$ICON"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGETS/Contents/MacOS"
# SwiftPM tells the linker the SDK is as old as the deployment target, and newer macOS then runs the
# app in compatibility mode, without its current look. So the real SDK version is written in here.
# (Passing it to the linker instead breaks with some SwiftPM versions, which hand -Xlinker flags to
# clang as they are.)
vtool -set-build-version macos "$MIN_MACOS" "$SDK" -replace -output "$APP/Contents/MacOS/Counts" "$BIN/Counts"
vtool -set-build-version macos "$MIN_MACOS" "$SDK" -replace -output "$WIDGETS/Contents/MacOS/CountsWidgets" \
  "$BIN/CountsWidgets"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# The widgets are an app extension, which carries the app's version and minimum macOS.
cp Resources/Widgets/Info.plist "$WIDGETS/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)" \
  "$WIDGETS/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$MIN_MACOS" "$WIDGETS/Contents/Info.plist"

# Every slice has to say what was asked for above, or the app would refuse to open on older macOS,
# or look dated on newer.
echo "==> Checking the binaries"
for binary in "$APP/Contents/MacOS/Counts" "$WIDGETS/Contents/MacOS/CountsWidgets"; do
  MINOS="$(vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }' | sort -u)"
  BUILT_SDK="$(vtool -show-build "$binary" | awk '$1 == "sdk" { print $2 }' | sort -u)"
  if [ "$MINOS" != "$MIN_MACOS" ] || [ "$BUILT_SDK" != "$SDK" ]; then
    echo "$(basename "$binary") is built for macOS $MINOS with SDK $BUILT_SDK, not macOS $MIN_MACOS with SDK $SDK." >&2
    exit 1
  fi
  echo "    $(basename "$binary"): $(lipo -archs "$binary"), macOS $MINOS and later, SDK $BUILT_SDK"
done

echo "==> Signing (ad hoc)"
# The widgets first, since signing the app seals what's inside it. They run sandboxed, with leave
# to read the timers.
codesign --force --sign - --entitlements Resources/Widgets/Widgets.entitlements "$WIDGETS"
codesign --force --sign - "$APP"

# Quit a running copy and wait for it to exit, or `open` can fail while it's still shutting down.
quit_counts() {
  pkill -x Counts || true
  while pgrep -x Counts >/dev/null; do sleep 0.1; done
}

case "$ACTION" in
  run)
    quit_counts
    open "$APP"
    ;;
  install)
    quit_counts
    mkdir -p "$(dirname "$INSTALLED")"
    rm -rf "$INSTALLED"
    ditto "$APP" "$INSTALLED"
    open "$INSTALLED"
    ;;
  *)
    echo "==> Built $APP"
    ;;
esac
