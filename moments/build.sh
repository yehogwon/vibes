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
WIDGETS="$APP/Contents/PlugIns/MomentsWidgets.appex"
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

# The oldest macOS Moments runs on. Package.swift has to agree, since the compiler checks what the
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGETS/Contents/MacOS" "$WIDGETS/Contents/Resources"
# SwiftPM tells the linker the SDK is as old as the deployment target, and newer macOS then runs the
# app in compatibility mode, without its current look. So the real SDK version is written in here.
# (Passing it to the linker instead breaks with some SwiftPM versions, which hand -Xlinker flags to
# clang as they are.)
vtool -set-build-version macos "$MIN_MACOS" "$SDK" -replace -output "$APP/Contents/MacOS/Moments" "$BIN/Moments"
vtool -set-build-version macos "$MIN_MACOS" "$SDK" -replace -output "$WIDGETS/Contents/MacOS/MomentsWidgets" \
  "$BIN/MomentsWidgets"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# The widgets are an app extension, which carries the app's version and minimum macOS.
cp Resources/Widgets/Info.plist "$WIDGETS/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)" \
  "$WIDGETS/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$MIN_MACOS" "$WIDGETS/Contents/Info.plist"

# The system reads a Moment widget's settings (which moment it shows) from App Intents metadata
# that Xcode would extract while building. SwiftPM doesn't, so it's extracted here, from the
# values the compiler noted down while building the widgets for Apple silicon.
echo "==> Extracting the widgets' App Intents"
INTERMEDIATES="$(dirname "$(dirname "$BIN")")/Intermediates.noindex"
find "$INTERMEDIATES" -path "*/$(basename "$BIN")/MomentsWidgets*.build/Objects-normal/arm64/*.swiftconstvalues" \
  -not -path '*testable*' > build/const-values.txt
if [ ! -s build/const-values.txt ]; then
  echo "The compiler noted no values for the widgets in $INTERMEDIATES." >&2
  exit 1
fi
find "$ROOT/Sources/MomentsWidgets" -name '*.swift' > build/widget-sources.txt
xcrun appintentsmetadataprocessor --output "$WIDGETS/Contents/Resources" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" --sdk-root "$(xcrun --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '$1 == "Build" { print $3 }')" --platform-family macOS \
  --deployment-target "$MIN_MACOS" --target-triple "arm64-apple-macos$MIN_MACOS" --module-name MomentsWidgets \
  --source-file-list build/widget-sources.txt --swift-const-vals-list build/const-values.txt \
  --deployment-aware-processing --no-app-shortcuts-localization
if [ ! -f "$WIDGETS/Contents/Resources/Metadata.appintents/extract.actionsdata" ]; then
  echo "The widgets' App Intents metadata wasn't written." >&2
  exit 1
fi

# Every slice has to say what was asked for above, or the app would refuse to open on older macOS,
# or look dated on newer.
echo "==> Checking the binaries"
for binary in "$APP/Contents/MacOS/Moments" "$WIDGETS/Contents/MacOS/MomentsWidgets"; do
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
# to read the moments.
codesign --force --sign - --entitlements Resources/Widgets/Widgets.entitlements "$WIDGETS"
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
