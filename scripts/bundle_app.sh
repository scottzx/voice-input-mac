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
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

MODEL_NAME="SenseVoiceSmall-Q8_0.gguf"
BUNDLE_MODEL="${BUNDLE_MODEL:-0}"

mkdir -p "$APP/Contents/Resources/models"

if [[ "$BUNDLE_MODEL" == "1" ]]; then
    MODEL_SRC="${VOICE_INPUT_MODEL:-}"
    if [[ -z "$MODEL_SRC" && -n "${TRANSCRIBE_CPP:-}" ]]; then
        MODEL_SRC="$TRANSCRIBE_CPP/models/$MODEL_NAME"
    fi
    if [[ -z "$MODEL_SRC" || ! -f "$MODEL_SRC" ]]; then
        MODEL_SRC="$HOME/.transcribe_models/$MODEL_NAME"
    fi
    if [[ -z "$MODEL_SRC" || ! -f "$MODEL_SRC" ]]; then
        MODEL_SRC="$HOME/.1agents/models/$MODEL_NAME"
    fi
    if [[ -z "$MODEL_SRC" || ! -f "$MODEL_SRC" ]]; then
        MODEL_SRC="$ROOT/../../1agents_app/reference_repo/transcribe.cpp/models/$MODEL_NAME"
    fi

    if [[ -f "$MODEL_SRC" ]]; then
        if ! cp -c "$MODEL_SRC" "$APP/Contents/Resources/models/$MODEL_NAME" 2>/dev/null; then
            cp "$MODEL_SRC" "$APP/Contents/Resources/models/$MODEL_NAME"
        fi
        echo "model: bundled $APP/Contents/Resources/models/$MODEL_NAME" >&2
    else
        echo "warning: BUNDLE_MODEL=1 specified but model $MODEL_NAME not found; skipping bundling" >&2
    fi
else
    echo "model: skipped bundling weights (using shared ~/.transcribe_models/ or on-demand download)" >&2
fi

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

# Local `make app` keeps Apple Development so Accessibility TCC survives rebuilds.
# `RELEASE_SIGN=1` (make release-dmg) uses Developer ID + hardened runtime.
sign_app() {
    local identity="${CODESIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        # Prefer the SHA-1 hash over the friendly name so duplicate identities
        # in the keychain don't fail codesign with "ambiguous".
        if [[ "${RELEASE_SIGN:-}" == "1" ]]; then
            identity="$(security find-identity -v -p codesigning 2>/dev/null \
                | awk '/Developer ID Application/ { print $2; exit }')"
        else
            identity="$(security find-identity -v -p codesigning 2>/dev/null \
                | awk '/Apple Development|Mac Developer/ { print $2; exit }')"
        fi
    fi
    xattr -cr "$APP" 2>/dev/null || true
    if [[ -z "$identity" ]]; then
        echo "codesign: ad-hoc (Accessibility will reset on every rebuild)" >&2
        codesign --force --deep --sign - "$APP"
        return
    fi
    echo "codesign: $identity" >&2
    local extra=()
    local app_extra=()
    if [[ "$identity" == Developer\ ID\ Application:* || "${RELEASE_SIGN:-}" == "1" ]]; then
        extra+=(--options runtime --timestamp)
        app_extra+=("${extra[@]}")
        if [[ -f "$ROOT/Resources/Release.entitlements" ]]; then
            app_extra+=(--entitlements "$ROOT/Resources/Release.entitlements")
        fi
    else
        extra+=(--timestamp=none)
        app_extra+=("${extra[@]}")
    fi
    local fw="$APP/Contents/Frameworks/CTranscribe.framework"
    if [[ -d "$fw" ]]; then
        codesign --force --sign "$identity" "${extra[@]}" "$fw"
    fi
    codesign --force --sign "$identity" "${app_extra[@]}" "$APP"
    codesign --verify --strict "$APP"
}
sign_app
echo "$APP"
