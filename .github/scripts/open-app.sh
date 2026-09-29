#!/bin/bash
# Opens an app and fails unless it's still running 10 seconds later. It runs in an empty folder of
# its own, so relative paths in the arguments land there.
#
#   open-app.sh APP.app [ARGUMENT...]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 APP.app [ARGUMENT...]" >&2
  exit 1
fi
APP="$(cd "$1" && pwd)"
shift
NAME="$(plutil -extract CFBundleName raw "$APP/Contents/Info.plist")"
EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")"

cd "$(mktemp -d)"
"$APP/Contents/MacOS/$EXECUTABLE" "$@" > app.log 2>&1 &
pid=$!
sleep 10
if ! kill -0 "$pid" 2>/dev/null; then
  echo "$NAME quit within 10 seconds of opening:" >&2
  cat app.log >&2
  exit 1
fi
kill "$pid"
echo "$NAME was still running after 10 seconds."
