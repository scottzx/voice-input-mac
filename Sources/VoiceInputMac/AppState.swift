import AppKit
import Combine
import Foundation
import VoiceInputCore

@MainActor
final class AppState: ObservableObject {
    enum Phase: String {
        case idle
        case preparing
        case listening
        case capturing
        case transcribing
        case error
    }

    static let shared = AppState()

    @Published var phase: Phase = .idle
    @Published var statusLine = "空闲"
    @Published var lastTranscript = ""
    @Published var errorMessage: String?
    @Published var modelReady = false
    @Published var modelPath: String?
    @Published var backendName = ""
    @Published var micGranted = false
    @Published var accessibilityTrusted = false
    @Published var sensitivity: Double = 0.55
    @Published var level: Float = 0
    @Published private(set) var listenMode: ListenMode = .off

    enum ListenMode {
        case off
        case hold
        case sticky
    }

    let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private let pipeline = AudioPipeline()
    private let transcribeQueue = DispatchQueue(label: "voice.input.transcribe", qos: .userInitiated)
    private var lastPasted = ""
    private var stopRequested = false
    private var pendingUtterances = 0
    private var speaking = false

    var isArmed: Bool {
        switch phase {
        case .preparing, .listening, .capturing, .transcribing: return true
        default: return false
        }
    }

    var menuIcon: String {
        switch phase {
        case .idle: return "mic"
        case .preparing: return "hourglass"
        case .listening: return "mic.and.signal.meter"
        case .capturing: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "mic.slash"
        }
    }

    func bootstrap() {
        hotkey.onHoldStart = { [weak self] in
            Task { @MainActor in self?.beginHold() }
        }
        hotkey.onHoldEnd = { [weak self] in
            Task { @MainActor in self?.endHold() }
        }
        hotkey.onStickyToggle = { [weak self] in
            Task { @MainActor in self?.toggleSticky() }
        }
        hotkey.register()
        refreshPermissions()
        pipeline.setSensitivity(Float(sensitivity))
        locateModel()
    }

    func locateModel() {
        if let url = ModelLocator.locate() {
            modelPath = url.path
            errorMessage = nil
        } else {
            modelPath = nil
            errorMessage = TranscriberError.modelMissing.localizedDescription
        }
    }

    func refreshPermissions() {
        accessibilityTrusted = inserter.isTrusted
        Task {
            micGranted = await AudioCapture.requestMicrophoneAccess()
        }
    }

    func setSensitivity(_ value: Double) {
        sensitivity = min(1, max(0, value))
        pipeline.setSensitivity(Float(sensitivity))
    }

    func toggle() {
        toggleSticky()
    }

    func beginHold() {
        if listenMode == .sticky { return }
        listenMode = .hold
        if !isArmed {
            startListening()
        } else {
            statusLine = listeningHint
        }
    }

    func endHold() {
        guard listenMode == .hold else { return }
        listenMode = .off
        stopListening()
    }

    func toggleSticky() {
        if listenMode == .sticky {
            listenMode = .off
            stopListening()
            return
        }
        listenMode = .sticky
        if !isArmed {
            startListening()
        } else {
            statusLine = listeningHint
        }
    }

    private var listeningHint: String {
        switch listenMode {
        case .sticky: return "等待说话 · 双击右 ⌥ 结束"
        case .hold: return "等待说话 · 松开右 ⌥ 结束"
        case .off: return "等待说话"
        }
    }

    func startListening() {
        errorMessage = nil
        stopRequested = false
        lastPasted = ""
        locateModel()
        guard let modelPath else {
            phase = .error
            statusLine = "缺少模型"
            listenMode = .off
            return
        }
        phase = .preparing
        statusLine = "加载模型…"
        refreshPermissions()
        Task {
            let granted = await AudioCapture.requestMicrophoneAccess()
            micGranted = granted
            guard granted else {
                phase = .error
                statusLine = "需要麦克风权限"
                errorMessage = "在系统设置 › 隐私与安全性 › 麦克风 中允许 VoiceInputMac。"
                listenMode = .off
                return
            }
            do {
                try transcriber.load(modelURL: URL(fileURLWithPath: modelPath))
                modelReady = true
                backendName = transcriber.backendName
                pipeline.reset()
                speaking = false
                let pipeline = self.pipeline
                try capture.start { [weak self] samples in
                    pipeline.process(samples) { snapshot in
                        Task { @MainActor in
                            self?.applyAudio(snapshot)
                        }
                    }
                }
                guard !self.stopRequested else {
                    self.capture.stop()
                    self.phase = .idle
                    self.statusLine = "空闲"
                    self.listenMode = .off
                    return
                }
                phase = .listening
                statusLine = listeningHint
                accessibilityTrusted = inserter.isTrusted
                if !inserter.isTrusted {
                    errorMessage = "辅助功能未对本版本生效。打开系统设置 › 隐私与安全性 › 辅助功能，去掉 VoiceInputMac 再重新勾选。"
                }
            } catch {
                phase = .error
                statusLine = "启动失败"
                errorMessage = error.localizedDescription
                listenMode = .off
            }
        }
    }

    func stopListening() {
        stopRequested = true
        capture.stop()
        pipeline.flush { [weak self] flushed in
            Task { @MainActor in
                guard let self else { return }
                if let flushed {
                    self.handle(flushed)
                }
                if self.pendingUtterances == 0 {
                    self.phase = .idle
                    self.statusLine = "空闲"
                    self.listenMode = .off
                } else {
                    self.statusLine = "处理剩余片段…"
                }
            }
        }
    }

    func promptAccessibility() {
        inserter.promptAccessibility()
        inserter.openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func quit() {
        stopListening()
        transcriber.unload()
        NSApp.terminate(nil)
    }

    private func applyAudio(_ snapshot: AudioPipeline.Snapshot) {
        guard isArmed, !stopRequested else { return }
        speaking = snapshot.inSpeech
        level = snapshot.rms
        for event in snapshot.events {
            handle(event)
        }
        if snapshot.events.isEmpty, snapshot.inSpeech, phase == .listening {
            phase = .capturing
            statusLine = "说话中"
        }
    }

    private func handle(_ event: EnergyVAD.Event) {
        switch event {
        case .speechStart:
            if phase != .transcribing {
                phase = .capturing
            }
            statusLine = "说话中"
        case .discardedShort:
            if pendingUtterances == 0 && !stopRequested {
                phase = .listening
                statusLine = listeningHint
            }
        case .speechEnd(let pcm):
            enqueue(pcm)
        }
    }

    private func enqueue(_ pcm: [Float]) {
        pendingUtterances += 1
        phase = .transcribing
        statusLine = "识别中"
        transcribeQueue.async { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try self?.transcriber.transcribe(pcm) ?? "")
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in
                self?.finishUtterance(result)
            }
        }
    }

    private func finishUtterance(_ result: Result<String, Error>) {
        pendingUtterances = max(0, pendingUtterances - 1)
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            statusLine = "识别失败"
        case .success(let text):
            if TextCleanup.isUseful(text) {
                let glue = TextCleanup.glue(previous: lastPasted, incoming: text)
                let payload = glue + text
                lastPasted = text
                lastTranscript = text
                accessibilityTrusted = inserter.isTrusted
                let wrote = inserter.insert(payload)
                if !wrote || !inserter.isTrusted {
                    errorMessage = "识别成功但没能写入当前输入框。重新编译后系统会把辅助功能当成新应用：打开系统设置 › 隐私与安全性 › 辅助功能，去掉 VoiceInputMac 再重新勾选。"
                }
            }
        }
        if stopRequested && pendingUtterances == 0 {
            phase = .idle
            statusLine = lastTranscript.isEmpty ? "空闲" : lastTranscript
            return
        }
        if pendingUtterances > 0 {
            phase = .transcribing
            statusLine = "识别中"
        } else if speaking {
            phase = .capturing
            statusLine = "说话中"
        } else {
            phase = .listening
            statusLine = listeningHint
        }
        accessibilityTrusted = inserter.isTrusted
    }
}
