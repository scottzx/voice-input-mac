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
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus = ""
    @Published var backendName = ""
    @Published var micGranted = false
    @Published var accessibilityTrusted = false
    @Published var sensitivity: Double = 0.55
    @Published var level: Float = 0
    @Published var inputDevices: [AudioInputDevice] = []
    @Published var selectedInputUID = ""
    @Published var polisherConfig: PolisherConfig = PolisherConfig()
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isFetchingModels = false
    @Published private(set) var isPolishing = false
    @Published private(set) var listenMode: ListenMode = .off
    @Published var recordingKeyChoice: RecordingKeyChoice = .fn

    enum RecordingKeyChoice: String, CaseIterable, Identifiable {
        case fn = "fn"
        case leftCommand = "leftCommand"
        case rightCommand = "rightCommand"

        var id: String { rawValue }

        var display: String {
            switch self {
            case .fn: return "Fn / 地球仪 🌐（推荐，不冲突）"
            case .leftCommand: return "左 ⌘（Command）"
            case .rightCommand: return "右 ⌘（Command）"
            }
        }

        var chord: HotkeyMonitor.Chord {
            switch self {
            case .fn: return .fn
            case .leftCommand: return .leftCommand
            case .rightCommand: return .rightCommand
            }
        }
    }

    enum ListenMode {
        case off
        case hold
        case sticky
    }

    let recordingHotkey = HotkeyMonitor()
    let polishHotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private let pipeline = AudioPipeline()
    private let polisher = TextPolisher()
    private let transcribeQueue = DispatchQueue(label: "voice.input.transcribe", qos: .userInitiated)
    private var lastPasted = ""
    private var stopRequested = false
    private var pendingUtterances = 0
    private var speaking = false
    private let inputWatcher = AudioInputWatcher()
    private var missingInputSince: Date?
    private var polishSession = 0
    private static let recordingKeyChoiceKey = "recordingKeyChoice"
    private static let customModelKey = "customModelPath"
    private static let inputUIDKey = "inputDeviceUID"
    private static let polisherKey = "polisherConfig"
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

    func setRecordingKeyChoice(_ choice: RecordingKeyChoice) {
        recordingKeyChoice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.recordingKeyChoiceKey)
        registerRecordingHotkey()
    }

    private func registerRecordingHotkey() {
        recordingHotkey.onHoldStart = { [weak self] in
            Task { @MainActor in self?.beginHold() }
        }
        recordingHotkey.onHoldEnd = { [weak self] in
            Task { @MainActor in self?.endHold() }
        }
        recordingHotkey.onClickToggle = { [weak self] in
            Task { @MainActor in self?.toggleSticky() }
        }
        recordingHotkey.register(recordingKeyChoice.chord)
    }

    func bootstrap() {
        loadPolisherConfig()
        let savedKey = UserDefaults.standard.string(forKey: Self.recordingKeyChoiceKey)
        recordingKeyChoice = savedKey.flatMap(RecordingKeyChoice.init(rawValue:)) ?? .fn
        registerRecordingHotkey()

        // Right ⌥: single tap or double tap polishes the selection.
        polishHotkey.singleTapImmediate = true
        polishHotkey.onClickToggle = { [weak self] in
            Task { @MainActor in self?.polishSelection() }
        }
        polishHotkey.onDoubleClickPolish = { [weak self] in
            Task { @MainActor in self?.polishSelection() }
        }
        polishHotkey.register(.rightOption)
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

    func updatePolisherConfig(_ config: PolisherConfig) {
        polisherConfig = config
        polisher.config = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.polisherKey)
        }
    }

    func fetchAvailableModels() {
        guard polisherConfig.isConfigured else {
            errorMessage = "请先填写 Base URL 和 API Key"
            return
        }
        guard !isFetchingModels else { return }
        isFetchingModels = true
        errorMessage = nil
        Task {
            do {
                let models = try await polisher.listModels()
                await MainActor.run {
                    self.availableModels = models
                    self.isFetchingModels = false
                    self.statusLine = "已获取 \(models.count) 个模型"
                }
            } catch {
                await MainActor.run {
                    self.isFetchingModels = false
                    self.errorMessage = "获取模型列表失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func loadPolisherConfig() {
        guard let data = UserDefaults.standard.data(forKey: Self.polisherKey),
              let stored = try? JSONDecoder().decode(PolisherConfig.self, from: data) else {
            return
        }
        polisherConfig = stored
        polisher.config = stored
    }

    var isSharedModel: Bool {
        guard let modelPath else { return false }
        return modelPath.contains(".transcribe_models")
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
                errorMessage = "自定义模型不可用，已改用默认共享模型"
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

    func useDefaultModel() {
        UserDefaults.standard.removeObject(forKey: Self.customModelKey)
        reloadModel()
    }

    func useBundledModel() {
        useDefaultModel()
    }

    func downloadRecommendedModel() {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        downloadProgress = 0.01
        downloadStatus = "正在连接 ModelScope 镜像源..."
        errorMessage = nil

        Task { [weak self] in
            do {
                _ = try await ModelDownloader.shared.downloadRecommendedModel { percent, status in
                    Task { @MainActor in
                        AppState.shared.downloadProgress = percent
                        AppState.shared.downloadStatus = status
                    }
                }
                await MainActor.run { [weak self] in
                    self?.isDownloadingModel = false
                    self?.downloadProgress = 1.0
                    self?.downloadStatus = "下载完成"
                    self?.useDefaultModel()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isDownloadingModel = false
                    self?.errorMessage = "模型下载失败: \(error.localizedDescription)"
                }
            }
        }
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
        case .sticky: return "等待输入"
        case .hold: return "等待输入"
        case .off: return "等待输入"
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

    func polishSelection() {
        guard !isPolishing else { return }
        guard polisherConfig.isConfigured else {
            flashPolishFeedback("整理功能未启用，请在设置里启用并填写 API key。", isError: true)
            return
        }
        guard inserter.isTrusted else {
            flashPolishFeedback(
                "整理需要「辅助功能」权限。打开系统设置 › 隐私与安全性 › 辅助功能，勾上 VoiceInputMac。",
                isError: true
            )
            return
        }

        guard let input = inserter.readSelection(), !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            flashPolishFeedback("请先在其它 App 里选中要整理的文字。", isError: true)
            return
        }

        polishSession += 1
        let session = polishSession
        isPolishing = true
        statusLine = "整理中…"
        Task {
            do {
                let polished = try await polisher.polish(input)
                await MainActor.run {
                    guard self.polishSession == session else { return }
                    self.applyPolished(polished, session: session)
                }
            } catch {
                await MainActor.run {
                    guard self.polishSession == session else { return }
                    self.flashPolishFeedback(error.localizedDescription, isError: true)
                }
            }
        }
    }

    /// Briefly arm the polish HUD so the user sees feedback even when the
    /// polish aborts before the network call (no selection / not configured).
    private func flashPolishFeedback(_ message: String, isError: Bool) {
        polishSession += 1
        let session = polishSession
        isPolishing = true
        statusLine = message
        if isError {
            errorMessage = message
        } else {
            errorMessage = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.polishSession == session else { return }
            self.isPolishing = false
            if self.statusLine == message {
                self.statusLine = "空闲"
            }
        }
    }

    private func applyPolished(_ polished: String, session: Int) {
        defer { isPolishing = false }
        guard !polished.isEmpty else {
            flashPolishFeedback("整理结果为空", isError: true)
            return
        }
        // `insert` already tries `insertViaAX` (which sets the focused element's
        // selected text) before falling back to unicode keystrokes / paste, so a
        // single call replaces the selection in every app that supports it and
        // degrades gracefully otherwise.
        if inserter.insert(polished) {
            statusLine = "已整理"
        } else {
            statusLine = "整理完成但未能写入"
            errorMessage = "整理完成但没找到可写入的位置。"
        }
        lastTranscript = polished
        lastPasted = polished

        let currentStatus = statusLine
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.polishSession == session else { return }
            if self.statusLine == currentStatus {
                self.statusLine = "空闲"
            }
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
