#!/bin/bash
# Checks casks with brew style and brew audit. TAP is a folder laid out like yehogwon/homebrew-vibes
# (the real one, or one with just Casks/<cask>.rb in it), and it's tapped as yehogwon/vibes, so this
# is for CI runners: it stops if that tap is already there.
#
#   audit-casks.sh TAP CASK...
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 TAP CASK..." >&2
  exit 1
fi
TAP="$(cd "$1" && pwd)"
shift

LINK="$(brew --repository)/Library/Taps/yehogwon/homebrew-vibes"
if [ -e "$LINK" ] && [ "$(readlink "$LINK")" != "$TAP" ]; then
  echo "yehogwon/vibes is already tapped at $LINK." >&2
  exit 1
fi
mkdir -p "$(dirname "$LINK")"
ln -sfn "$TAP" "$LINK"

CASKS=()
for cask in "$@"; do
  CASKS+=("yehogwon/vibes/$cask")
done
# The casks clear quarantine in a postflight block, which Cask/InstallSteps rejects; each cask
# explains why it can't be postflight_steps.
brew style --except-cops Cask/InstallSteps "${CASKS[@]}"
brew audit --cask --strict "${CASKS[@]}"
