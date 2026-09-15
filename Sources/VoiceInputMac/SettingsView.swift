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
                Text("双击右 ⌥：保持听写，再双击关闭。长按右 ⌥：按住说话，松开关闭。说话由音量 VAD 自动切段，每段识别完立刻粘贴到当前光标。需要辅助功能权限才能在其它 App 里收到热键。")
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
        .frame(width: 480, height: 480)
        .onAppear {
            state.refreshPermissions()
            state.refreshInputDevices()
        }
    }
}
