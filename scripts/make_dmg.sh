#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
OUTDIR="${2:-$ROOT/dist}"

if [[ -z "$APP" ]]; then
    if [[ -d "$ROOT/VoiceInputMac.app" ]]; then
        APP="$ROOT/VoiceInputMac.app"
    elif [[ -d "$HOME/Applications/VoiceInputMac.app" ]]; then
        APP="$HOME/Applications/VoiceInputMac.app"
    else
        echo "error: VoiceInputMac.app not found (run make app or make install)" >&2
        exit 1
    fi
fi

if [[ ! -d "$APP" ]]; then
    echo "error: not an app bundle: $APP" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VOLNAME="Voice Input ${VERSION}"
DMG="$OUTDIR/VoiceInputMac-${VERSION}.dmg"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voice-input-dmg.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

mkdir -p "$SCRATCH/stage" "$OUTDIR"
ditto "$APP" "$SCRATCH/stage/VoiceInputMac.app"
ln -s /Applications "$SCRATCH/stage/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$SCRATCH/stage" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG" >/dev/null

echo "$DMG"
echo "size: $(du -h "$DMG" | awk '{print $1}')" >&2
