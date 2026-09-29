#!/bin/bash
# Builds Moments.app from the SwiftPM package. Xcode has to be installed (the Command Line Tools
# lack SwiftUI's macro plugin), but it never opens.
#
#   ./build.sh           build a release Moments.app (Apple silicon and Intel) into build/
#   ./build.sh debug     build a debug copy instead
#   ./build.sh run       build a debug copy and open it (it appears in the menu bar)
#   ./build.sh install   build a release copy into ~/Applications and open it
#
# Run the tests with `swift test`.
#
# To try syncing without touching iCloud Drive, point a copy at other folders:
#   open -n build/Moments.app --args -MomentsSyncFolder /tmp/cloud -MomentsLocalFolder /tmp/mac-a
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Moments.app"
ICON="$ROOT/build/AppIcon.icns"
INSTALLED="$HOME/Applications/Moments.app"
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

BUILD=(-c "$CONFIG" --product Moments)
# Release builds also run on Intel Macs.
if [ "$CONFIG" = release ]; then
  BUILD+=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling ($CONFIG)"
swift build "${BUILD[@]}"
BIN="$(swift build "${BUILD[@]}" --show-bin-path)/Moments"

# The icon only changes when its script does, so it's drawn again only then.
if [ Tools/MakeIcon.swift -nt "$ICON" ]; then
  echo "==> Drawing icon"
  swift Tools/MakeIcon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o "$ICON"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Moments"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad hoc)"
codesign --force --sign - "$APP"

# Quit a running copy and wait for it to exit, or `open` can fail while it's still shutting down.
quit_moments() {
  pkill -x Moments || true
  while pgrep -x Moments >/dev/null; do sleep 0.1; done
}

case "$ACTION" in
  run)
    quit_moments
    open "$APP"
    ;;
  install)
    quit_moments
    mkdir -p "$(dirname "$INSTALLED")"
    rm -rf "$INSTALLED"
    ditto "$APP" "$INSTALLED"
    open "$INSTALLED"
    ;;
  *)
    echo "==> Built $APP"
    ;;
esac
