# Voice Input for Mac

本机离线语音输入。菜单栏常驻，热键打开听写后，按音量 VAD 自动切段，每段用 `transcribe.cpp` 的 SenseVoiceSmall 在 Metal 上识别，再粘贴到当前光标。音频不出本机，也不接 1Agents。

## 行为

1. **单击左 ⌘**：切换持续听写开关。
2. **长按左 ⌘**：按住期间听写，松开结束。
3. **单击或双击右 ⌥**：让大模型整理当前 App 里选中的文字，没有选区时会提示先选中。
4. 音量超过环境底噪 → 开始录一段。
4. 静音超过约 550 ms → 这一段结束，立即识别并 `⌘V` 到当前 App。上一句识别时仍可继续说下一句。
5. 菜单「开始持续听写」和单击右 ⌥ 相同。热键需要辅助功能权限。
6. 菜单里可选麦克风（系统默认 / 内置 / 蓝牙 / USB）。AirPods 戴上或摘下后列表会自己更新。
7. 单击或双击右 ⌥ 的整理功能需要在设置里启用并填写 OpenAI 兼容的 Base URL / API Key / 模型名（OpenAI、DeepSeek、Moonshot、自建网关、本地 Ollama 兼容入口都可以）。

默认模型：`SenseVoiceSmall-Q8_0.gguf`（中英日韩，单段最长约 28 秒）。`make app` 会把这份权重拷进 `VoiceInputMac.app/Contents/Resources/models/`，用户打开就能用。设置里可以改选其他 `.gguf`。

## 要求

- Apple Silicon，macOS 14+
- cmake、ninja、Xcode CLT
- 本机已有 `transcribe.cpp`（开发机上在 `1agents_app/reference_repo/transcribe.cpp`）
- 打包时能找到默认模型（约 241 MB）：

```text
$VOICE_INPUT_MODEL
$TRANSCRIBE_CPP/models/SenseVoiceSmall-Q8_0.gguf
```

运行时查找顺序：用户在设置里选的模型 → `$VOICE_INPUT_MODEL` → 应用包内置模型 → 本机 Application Support / `~/.voice_input_mac` / `~/.1agents` / 开发目录。

`~/.1agents/models/` 里那条软链若指向已经不存在的文件，应用会跳过。

## 构建

```bash
cd services/voice_input_mac
make            # 编 macOS xcframework + 应用
make run        # 打开 VoiceInputMac.app
make test
make install    # 拷到 ~/Applications/VoiceInputMac.app，给别人先用这版
make dmg        # 打成 dist/VoiceInputMac-<version>.dmg，拖进「应用程序」即可
make signed-dmg # Developer ID 签名后的 dmg（给外人装还要公证）
make release-dmg # 签名 + 公证，别人双击就能装
```

对外分发前先存公证密码（Apple ID 的 App 专用密码，不是登录密码）：

```bash
xcrun notarytool store-credentials VoiceInputNotary \
  --apple-id "xiaofeng.zeng@qq.com" \
  --team-id "3HJ3R6SXAL" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

第一次 `make native` 会编 ggml/Metal，大概几分钟。之后只改 Swift 时 `make app` 即可。

自定义 transcribe.cpp 路径：

```bash
make TRANSCRIBE_CPP=/path/to/transcribe.cpp
```

## 权限

- **麦克风**：第一次开始听写时系统会问。
- **辅助功能**：要把字写进其它 App，需要在「系统设置 › 隐私与安全性 › 辅助功能」里勾选 VoiceInputMac。没有这项权限时仍会识别，只是粘贴失败。
- 每次用临时 ad-hoc 签名打包，系统都会把它当成新应用。`make` 会尽量用本机的 `Apple Development` 证书签名，这样重新编译后不用再授权。如果刚换过签名方式，需要**去掉勾选再重新勾选一次**。

应用是 `LSUIElement`，Dock 里没有图标，只在菜单栏。

## 目录

```text
Sources/VoiceInputCore   VAD、采集、模型定位、识别、粘贴、热键
Sources/VoiceInputMac    菜单栏、状态浮层、设置
Vendor/                  本地编出来的 CTranscribe.xcframework（不入库）
```
