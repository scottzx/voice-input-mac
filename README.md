# Voice Input for Mac

本机离线语音输入。菜单栏常驻，热键打开听写后，按音量 VAD 自动切段，每段用 `transcribe.cpp` 的 SenseVoiceSmall 在 Metal 上识别，再粘贴到当前光标。音频不出本机，也不接 1Agents。

## 行为

1. **双击右 ⌥**：进入持续听写，再双击关闭。
2. **长按右 ⌥**：按住期间听写，松开结束。
3. 音量超过环境底噪 → 开始录一段。
4. 静音超过约 550 ms → 这一段结束，立即识别并 `⌘V` 到当前 App。
5. 菜单「开始持续听写」和双击右 ⌥ 相同。热键需要辅助功能权限。

默认模型：`SenseVoiceSmall-Q8_0.gguf`（中英日韩，单段最长约 28 秒）。

## 要求

- Apple Silicon，macOS 13+
- cmake、ninja、Xcode CLT
- 本机已有 `transcribe.cpp`（开发机上在 `1agents_app/reference_repo/transcribe.cpp`）
- 模型文件，按这个顺序找：

```text
$VOICE_INPUT_MODEL
~/Library/Application Support/VoiceInputMac/models/SenseVoiceSmall-Q8_0.gguf
~/.voice_input_mac/models/SenseVoiceSmall-Q8_0.gguf
~/.1agents/models/SenseVoiceSmall-Q8_0.gguf
$TRANSCRIBE_CPP/models/SenseVoiceSmall-Q8_0.gguf
```

当前开发机上的完整模型在：

`1agents_app/reference_repo/transcribe.cpp/models/SenseVoiceSmall-Q8_0.gguf`

`~/.1agents/models/` 里那条软链指向已经不存在的 `modules/transcribe.cpp`，应用会跳过损坏的占位文件。

## 构建

```bash
cd services/voice_input_mac
make            # 编 macOS xcframework + 应用
make run        # 打开 VoiceInputMac.app
make test
make install    # 拷到 ~/Applications
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
