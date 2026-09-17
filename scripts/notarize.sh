#!/usr/bin/env bash
set -euo pipefail

DMG="${1:-}"
PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-VoiceInputNotary}"

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
    echo "usage: $0 <VoiceInputMac-x.y.z.dmg>" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "error: 还没有公证登录（keychain profile: $PROFILE）" >&2
    echo "先到 https://appleid.apple.com 生成 App 专用密码，然后执行：" >&2
    echo >&2
    echo "  xcrun notarytool store-credentials $PROFILE \\" >&2
    echo "    --apple-id \"xiaofeng.zeng@qq.com\" \\" >&2
    echo "    --team-id \"3HJ3R6SXAL\" \\" >&2
    echo "    --password \"xxxx-xxxx-xxxx-xxxx\"" >&2
    echo >&2
    echo "存好后再跑: make notarize" >&2
    exit 2
fi

echo "notary: submit $DMG (profile $PROFILE)" >&2
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "notarized: $DMG" >&2
