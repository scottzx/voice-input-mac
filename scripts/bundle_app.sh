#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$ROOT/.build/release/VoiceInputMac}"
APP="${2:-$ROOT/VoiceInputMac.app}"
FRAMEWORK_SRC="${TRANSCRIBE_XCFRAMEWORK_PATH:-$ROOT/Vendor/TranscribeCpp.xcframework}"

if [[ ! -x "$BIN" ]]; then
    echo "error: missing binary $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/VoiceInputMac"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM copies the CTranscribe framework next to the executable or under
# .build; also accept the xcframework macos slice.
copy_framework() {
    local src="$1"
    if [[ -d "$src" ]]; then
        rsync -a "$src" "$APP/Contents/Frameworks/"
        return 0
    fi
    return 1
}

FOUND=0
for candidate in \
    "$(dirname "$BIN")/CTranscribe.framework" \
    "$ROOT/.build/arm64-apple-macosx/release/CTranscribe.framework" \
    "$FRAMEWORK_SRC/macos-arm64/CTranscribe.framework" \
    "$FRAMEWORK_SRC/macos-arm64_x86_64/CTranscribe.framework"
do
    if copy_framework "$candidate"; then
        FOUND=1
        break
    fi
done

if [[ "$FOUND" -eq 0 ]]; then
    echo "warning: CTranscribe.framework not found; the app may fail to launch" >&2
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/VoiceInputMac" 2>/dev/null || true

# Ad-hoc signatures change every rebuild and drop Accessibility trust.
# Prefer a stable local development identity so TCC survives `make run`.
sign_app() {
    local identity="${CODESIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        identity="$(security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'\"' '/Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')"
    fi
    if [[ -n "$identity" ]]; then
        echo "codesign: $identity" >&2
        codesign --force --deep --sign "$identity" --timestamp=none "$APP"
    else
        echo "codesign: ad-hoc (Accessibility will reset on every rebuild)" >&2
        codesign --force --deep --sign - "$APP"
    fi
}
sign_app
echo "$APP"
