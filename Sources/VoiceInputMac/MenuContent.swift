import AppKit
import SwiftUI
import VoiceInputCore

struct MenuContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(state.listenMode == .sticky ? "停止持续听写" : "开始持续听写") {
                state.toggle()
            }
            Text("双击右 ⌥ 保持听写，再双击关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("长按右 ⌥ 说话，松开关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("打开设置")
                }
            } else {
                Button("打开设置") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Divider()
            Button("退出") {
                state.quit()
            }
        }
        .padding(.vertical, 4)
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.statusLine)
            Text(modelCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelCaption: String {
        if let path = state.modelPath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let backend = state.backendName.isEmpty ? "未加载" : state.backendName
            return "\(name) · \(backend)"
        }
        return "未找到模型"
    }

    private var optionalLast: String? {
        state.lastTranscript.isEmpty ? nil : state.lastTranscript
    }
}
