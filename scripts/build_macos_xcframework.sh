#!/usr/bin/env bash
# Build a macOS-arm64 CTranscribe.xcframework for VoiceInputMac.
# Only the host Apple Silicon slice (Metal embedded). Does not touch the
# transcribe.cpp tree's existing iOS xcframework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRANSCRIBE_CPP="${TRANSCRIBE_CPP:-}"
if [[ -z "$TRANSCRIBE_CPP" ]]; then
    for candidate in \
        "$ROOT/vendor/transcribe.cpp" \
        "$ROOT/../../1agents_app/reference_repo/transcribe.cpp" \
        "$HOME/Documents/01-开发项目/1agents/1agents_app/reference_repo/transcribe.cpp"
    do
        if [[ -f "$candidate/include/transcribe.h" ]]; then
            TRANSCRIBE_CPP="$(cd "$candidate" && pwd)"
            break
        fi
    done
fi
if [[ -z "${TRANSCRIBE_CPP}" || ! -f "$TRANSCRIBE_CPP/include/transcribe.h" ]]; then
    echo "error: transcribe.cpp not found. Set TRANSCRIBE_CPP to the repo root." >&2
    exit 1
fi

OUT_XCFRAMEWORK="${1:-$ROOT/Vendor/TranscribeCpp.xcframework}"
BUILD_ROOT="$ROOT/tmp/native-build"
FRAMEWORK_NAME="CTranscribe"
MACOS_MIN="${MACOS_MIN_OS_VERSION:-13.0}"
INSTALL_NAME="@rpath/${FRAMEWORK_NAME}.framework/Versions/Current/${FRAMEWORK_NAME}"

if command -v ninja >/dev/null 2>&1; then
    GENERATOR="Ninja"
else
    GENERATOR="Unix Makefiles"
fi

log() { printf '\n=== %s ===\n' "$*" >&2; }

rm -rf "$BUILD_ROOT" "$OUT_XCFRAMEWORK"
mkdir -p "$BUILD_ROOT"

log "configure transcribe.cpp (macos/arm64 Metal) at $TRANSCRIBE_CPP"
cmake -B "$BUILD_ROOT/cmake" -S "$TRANSCRIBE_CPP" -G "$GENERATOR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
    -DTRANSCRIBE_BUILD_SHARED=OFF \
    -DTRANSCRIBE_BUILD_TESTS=OFF \
    -DTRANSCRIBE_BUILD_EXAMPLES=OFF \
    -DTRANSCRIBE_BUILD_TOOLS=OFF \
    -DTRANSCRIBE_INSTALL=OFF \
    -DTRANSCRIBE_USE_OPENMP=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_NATIVE=OFF \
    -DTRANSCRIBE_METAL=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

log "build libtranscribe"
cmake --build "$BUILD_ROOT/cmake" --target transcribe --config Release --parallel

DYLIB="$BUILD_ROOT/CTranscribe.dylib"
force_args=()
while IFS= read -r a; do
    [[ -n "$a" ]] && force_args+=(-Wl,-force_load,"$a")
done < <(find "$BUILD_ROOT/cmake" \( -name 'libtranscribe.a' -o -name 'libggml*.a' \) | sort)

if [[ ${#force_args[@]} -eq 0 ]]; then
    echo "error: no libtranscribe.a / libggml*.a under $BUILD_ROOT/cmake" >&2
    exit 1
fi

log "link dylib"
xcrun -sdk macosx clang++ -dynamiclib \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -arch arm64 \
    -mmacosx-version-min="$MACOS_MIN" \
    "${force_args[@]}" \
    -framework Foundation -framework Metal -framework MetalKit -framework Accelerate \
    -lc++ -lz \
    -install_name "$INSTALL_NAME" \
    -o "$DYLIB"

FW="$BUILD_ROOT/fw/${FRAMEWORK_NAME}.framework"
rm -rf "$FW"
mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Modules" "$FW/Versions/A/Resources"
ln -sf A "$FW/Versions/Current"
ln -sf Versions/Current/Headers "$FW/Headers"
ln -sf Versions/Current/Modules "$FW/Modules"
ln -sf Versions/Current/Resources "$FW/Resources"
ln -sf "Versions/Current/${FRAMEWORK_NAME}" "$FW/${FRAMEWORK_NAME}"

cp "$DYLIB" "$FW/Versions/A/${FRAMEWORK_NAME}"
cp "$TRANSCRIBE_CPP/include/transcribe.h" "$FW/Versions/A/Headers/transcribe.h"
cp "$TRANSCRIBE_CPP/include/transcribe/"*.h "$FW/Versions/A/Headers/"
/usr/bin/sed -i '' 's|#include "transcribe/|#include "|g' "$FW/Versions/A/Headers"/*.h

{
    echo "framework module ${FRAMEWORK_NAME} {"
    for h in "$FW/Versions/A/Headers"/*.h; do
        echo "    header \"$(basename "$h")\""
    done
    cat <<EOF

    link "c++"
    link "z"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF
} > "$FW/Versions/A/Modules/module.modulemap"

cat > "$FW/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.transcribe.${FRAMEWORK_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MACOS_MIN}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>DTPlatformName</key>
    <string>macosx</string>
</dict>
</plist>
EOF

codesign --force --sign - --timestamp=none "$FW" >/dev/null 2>&1 || true

log "create xcframework -> $OUT_XCFRAMEWORK"
mkdir -p "$(dirname "$OUT_XCFRAMEWORK")"
xcodebuild -create-xcframework \
    -framework "$FW" \
    -output "$OUT_XCFRAMEWORK"

log "done"
find "$OUT_XCFRAMEWORK" -maxdepth 2 -type d | sort >&2
