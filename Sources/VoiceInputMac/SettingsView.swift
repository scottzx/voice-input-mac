import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
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
                Text(state.modelPath ?? "未找到 SenseVoiceSmall-Q8_0.gguf")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if !state.backendName.isEmpty {
                    Text("后端 \(state.backendName)")
                }
                Button("重新查找模型") {
                    state.locateModel()
                }
            }
            Section("权限") {
                LabeledContent("麦克风", value: state.micGranted ? "已授权" : "未授权")
                LabeledContent("辅助功能", value: state.accessibilityTrusted ? "已授权" : "未授权")
                Button("授予辅助功能…") {
                    state.promptAccessibility()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .onAppear { state.refreshPermissions() }
    }
}
