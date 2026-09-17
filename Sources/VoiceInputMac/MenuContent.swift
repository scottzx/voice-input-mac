import AppKit
import SwiftUI
import VoiceInputCore

struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(state.listenMode == .sticky ? "停止持续听写" : "开始持续听写") {
                state.toggle()
            }
            Button("整理选中内容") {
                state.polishSelection()
            }
            .disabled(!state.polisherConfig.isConfigured || state.isPolishing)
            Text("单击左 ⌘ 切换听写")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("长按左 ⌘ 说话，松开关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("单击或双击右 ⌥ 让大模型整理选中的文字")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("麦克风")
            Button(menuCheck(state.selectedInputUID.isEmpty) + "系统默认") {
                state.setInputDevice(uid: "")
            }
            ForEach(state.inputDevices) { device in
                Button(menuCheck(state.selectedInputUID == device.uid) + device.menuLabel) {
                    state.setInputDevice(uid: device.uid)
                }
            }
            Divider()
            statusRow
            if let last = optionalLast {
                Text(last)
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: 280, alignment: .leading)
            }
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 280, alignment: .leading)
            }
            Divider()
            Button(state.accessibilityTrusted ? "辅助功能已授权" : "授予辅助功能权限…") {
                state.promptAccessibility()
            }
            .disabled(state.accessibilityTrusted)
            Button("打开设置") {
                state.openSettings()
                openSettings()
            }
            Divider()
            Button("退出") {
                state.quit()
            }
        }
        .padding(.vertical, 4)
        .onAppear { state.refreshInputDevices() }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.statusLine)
            Text(modelCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state.currentInputLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelCaption: String {
        if let path = state.modelPath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let origin = state.usingBundledModel ? "内置" : "自定义"
            let backend = state.backendName.isEmpty ? "未加载" : state.backendName
            return "\(origin) \(name) · \(backend)"
        }
        return "未找到模型"
    }

    private var optionalLast: String? {
        state.lastTranscript.isEmpty ? nil : state.lastTranscript
    }

    private func menuCheck(_ on: Bool) -> String {
        on ? "✓ " : "    "
    }
}
