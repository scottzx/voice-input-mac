import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
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
    @Published var usingBundledModel = false
    @Published var backendName = ""
    @Published var micGranted = false
    @Published var accessibilityTrusted = false
    @Published var sensitivity: Double = 0.55
    @Published var level: Float = 0
    @Published var inputDevices: [AudioInputDevice] = []
    @Published var selectedInputUID = ""
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
    private let inputWatcher = AudioInputWatcher()
    private var missingInputSince: Date?
    private static let customModelKey = "customModelPath"
    private static let inputUIDKey = "inputDeviceUID"
    private static let missingInputGrace: TimeInterval = 2.0

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
        refreshInputDevices()
        capture.onConfigurationChange = { [weak self] in
            Task { @MainActor in self?.handleInputDevicesChanged() }
        }
        inputWatcher.start { [weak self] in
            Task { @MainActor in self?.handleInputDevicesChanged() }
        }
    }

    func locateModel() {
        let custom = UserDefaults.standard.string(forKey: Self.customModelKey)
            .map { URL(fileURLWithPath: $0) }
        var extras: [URL] = []
        if let bundled = ModelLocator.bundledModelsDirectory() {
            extras.append(bundled)
        }
        if let url = ModelLocator.locate(extraRoots: extras, userOverride: custom) {
            modelPath = url.path
            usingBundledModel = bundledModelURL.map { $0.standardizedFileURL.path == url.standardizedFileURL.path } ?? false
            if let custom, !ModelLocator.isUsableModel(custom) {
                errorMessage = "自定义模型不可用，已改用内置模型"
            } else {
                errorMessage = nil
            }
        } else {
            modelPath = nil
            usingBundledModel = false
            errorMessage = TranscriberError.modelMissing.localizedDescription
        }
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.title = "选择识别模型"
        panel.prompt = "使用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ModelLocator.isUsableModel(url) else {
            errorMessage = "这个文件不像是可用的识别模型"
            return
        }
        UserDefaults.standard.set(url.path, forKey: Self.customModelKey)
        reloadModel()
    }

    func useBundledModel() {
        UserDefaults.standard.removeObject(forKey: Self.customModelKey)
        reloadModel()
    }

    private func reloadModel() {
        transcriber.unload()
        modelReady = false
        backendName = ""
        locateModel()
    }

    private var bundledModelURL: URL? {
        ModelLocator.bundledModelsDirectory()?.appendingPathComponent(ModelLocator.defaultFileName)
    }

    func refreshPermissions() {
        accessibilityTrusted = inserter.isTrusted
        Task {
            micGranted = await AudioCapture.requestMicrophoneAccess()
        }
    }

    func refreshInputDevices() {
        inputDevices = AudioInputs.list()
        let saved = UserDefaults.standard.string(forKey: Self.inputUIDKey) ?? ""
        if saved.isEmpty {
            selectedInputUID = ""
            missingInputSince = nil
            return
        }
        if inputDevices.contains(where: { $0.uid == saved }) {
            selectedInputUID = saved
            missingInputSince = nil
            return
        }
        selectedInputUID = saved
        let now = Date()
        if missingInputSince == nil {
            missingInputSince = now
            return
        }
        guard now.timeIntervalSince(missingInputSince!) >= Self.missingInputGrace else { return }
        selectedInputUID = ""
        UserDefaults.standard.removeObject(forKey: Self.inputUIDKey)
        missingInputSince = nil
        if errorMessage == nil {
            errorMessage = "上次选择的麦克风已断开，已改用系统默认"
        }
    }

    func setInputDevice(uid: String) {
        missingInputSince = nil
        selectedInputUID = uid
        if uid.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.inputUIDKey)
        } else {
            UserDefaults.standard.set(uid, forKey: Self.inputUIDKey)
        }
        restartCaptureKeepingUI()
    }

    private func handleInputDevicesChanged() {
        let oldDefault = inputDevices.first(where: \.isDefault)?.uid
        let oldSelected = selectedInputUID
        let oldDeviceID = inputDevices.first(where: { $0.uid == oldSelected })?.deviceID
        refreshInputDevices()
        let newDefault = inputDevices.first(where: \.isDefault)?.uid
        let newDeviceID = inputDevices.first(where: { $0.uid == selectedInputUID })?.deviceID
        let selectedLost = !oldSelected.isEmpty && selectedInputUID != oldSelected
        let defaultChanged = oldDefault != newDefault
        let usingDefault = selectedInputUID.isEmpty
        let deviceReappeared = oldSelected == selectedInputUID
            && !selectedInputUID.isEmpty
            && oldDeviceID != newDeviceID
        guard isArmed, !stopRequested, phase != .preparing else { return }
        if selectedLost || deviceReappeared || (usingDefault && defaultChanged) {
            restartCaptureKeepingUI()
        }
    }

    private func restartCaptureKeepingUI() {
        guard isArmed, !stopRequested, phase != .preparing else { return }
        do {
            try startCapture()
            if pendingUtterances > 0 {
                phase = .transcribing
                statusLine = "识别中"
            } else {
                phase = .listening
                statusLine = listeningHint
            }
        } catch {
            stopRequested = true
            capture.stop()
            phase = .error
            statusLine = "麦克风切换失败"
            errorMessage = error.localizedDescription
            listenMode = .off
        }
    }

    var currentInputLabel: String {
        if selectedInputUID.isEmpty {
            if let def = inputDevices.first(where: \.isDefault) {
                return "系统默认 · \(def.name)"
            }
            return "系统默认"
        }
        return inputDevices.first(where: { $0.uid == selectedInputUID })?.menuLabel ?? "系统默认"
    }

    func openSettings() {
        refreshInputDevices()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                let typeName = String(describing: type(of: window))
                let looksLikeSettings = window.title.contains("设置")
                    || window.title.contains("Settings")
                    || typeName.contains("Settings")
                    || typeName.contains("Preferences")
                if looksLikeSettings {
                    window.makeKeyAndOrderFront(nil)
                }
            }
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
                refreshInputDevices()
                try startCapture()
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
        inputWatcher.stop()
        stopListening()
        transcriber.unload()
        NSApp.terminate(nil)
    }

    private func startCapture() throws {
        pipeline.reset()
        speaking = false
        let pipeline = self.pipeline
        let uid = selectedInputUID.isEmpty ? nil : selectedInputUID
        try capture.start(deviceUID: uid) { [weak self] samples in
            pipeline.process(samples) { snapshot in
                Task { @MainActor in
                    self?.applyAudio(snapshot)
                }
            }
        }
    }

    private func applyAudio(_ snapshot: AudioPipeline.Snapshot) {
        guard isArmed, !stopRequested else { return }
        speaking = snapshot.inSpeech
        level = snapshot.rms
        for event in snapshot.events {
            handle(event)
        }
        if snapshot.events.isEmpty, snapshot.inSpeech, phase == .listening || phase == .transcribing {
            phase = .capturing
            statusLine = "说话中"
        }
    }

    private func handle(_ event: EnergyVAD.Event) {
        switch event {
        case .speechStart:
            phase = .capturing
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
