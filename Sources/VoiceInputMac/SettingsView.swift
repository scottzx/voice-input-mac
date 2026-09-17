import SwiftUI
import VoiceInputCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("麦克风") {
                Picker("输入设备", selection: Binding(
                    get: { state.selectedInputUID },
                    set: { state.setInputDevice(uid: $0) }
                )) {
                    Text("系统默认").tag("")
                    ForEach(state.inputDevices) { device in
                        Text(device.menuLabel).tag(device.uid)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(state.currentInputLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("权限", value: state.micGranted ? "已授权" : "未授权")
            }
            Section("听写") {
                Text("单击左 ⌘：切换听写开关。长按左 ⌘：按住说话，松开关闭。单击或双击右 ⌥：让大模型整理当前 App 里选中的文字，没有选区时会提示先选中。说话由音量 VAD 自动切段，每段识别完立刻粘贴到当前光标。需要辅助功能权限才能在其它 App 里收到热键。")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { state.sensitivity },
                    set: { state.setSensitivity($0) }
                ), in: 0...1) {
                    Text("VAD 灵敏度")
                } minimumValueLabel: {
                    Text("迟钝")
                } maximumValueLabel: {
                    Text("灵敏")
                }
            }
            Section("整理") {
                Toggle("启用大模型整理", isOn: polisherBinding.enabled)
                TextField("Base URL", text: polisherBinding.baseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: polisherBinding.apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("模型名", text: polisherBinding.model)
                        .textFieldStyle(.roundedBorder)
                    Button(state.isFetchingModels ? "获取中…" : "刷新模型") {
                        state.fetchAvailableModels()
                    }
                    .disabled(state.isFetchingModels || state.polisherConfig.baseURL.isEmpty || state.polisherConfig.apiKey.isEmpty)
                }
                if !state.availableModels.isEmpty {
                    Picker("选择模型", selection: polisherBinding.model) {
                        Text("（手动输入）").tag("")
                        ForEach(state.availableModels, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                DisclosureGroup("系统提示词") {
                    TextEditor(text: polisherBinding.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 90)
                }
                Text("兼容 OpenAI Chat Completions 接口的任意服务都能用，例如 OpenAI / DeepSeek / Moonshot / 自建网关 / 本地 Ollama（配 OpenAI 兼容入口）。填好 Base URL 和 API Key 后点「刷新模型」会请求服务的 /models 列表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("模型") {
                Text(state.usingBundledModel ? "内置 \(ModelLocator.defaultFileName)" : (state.modelPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未找到识别模型"))
                Text(state.modelPath ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                if !state.backendName.isEmpty {
                    Text("后端 \(state.backendName)")
                }
                HStack {
                    Button("选择其他模型…") {
                        state.chooseModel()
                    }
                    Button("使用内置模型") {
                        state.useBundledModel()
                    }
                    .disabled(state.usingBundledModel)
                }
            }
            Section("权限") {
                LabeledContent("辅助功能", value: state.accessibilityTrusted ? "已授权" : "未授权")
                Button("授予辅助功能…") {
                    state.promptAccessibility()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 580)
        .onAppear {
            state.refreshPermissions()
            state.refreshInputDevices()
        }
    }

    private var polisherBinding: Binding<PolisherConfig> {
        Binding(
            get: { state.polisherConfig },
            set: { state.updatePolisherConfig($0) }
        )
    }
}
