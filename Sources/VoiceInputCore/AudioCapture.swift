import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

public final class AudioCapture {
    public static let sampleRate: Double = 16_000

    public enum CaptureError: Error, LocalizedError {
        case noInput
        case deviceMissing(String)
        case converter
        case engine(String)

        public var errorDescription: String? {
            switch self {
            case .noInput: return "没有可用的麦克风"
            case .deviceMissing: return "找不到上次选择的麦克风，请在设置里重新选择"
            case .converter: return "无法把麦克风采样转换成 16 kHz"
            case .engine(let message): return message
            }
        }
    }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outFormat: AVAudioFormat
    private var handler: (([Float]) -> Void)?
    private let lock = NSLock()
    private var configObserver: NSObjectProtocol?
    public var onConfigurationChange: (() -> Void)?

    public init() {
        outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    public var isRunning: Bool { engine.isRunning }

    public func start(deviceUID: String? = nil, handler: @escaping ([Float]) -> Void) throws {
        stop()
        self.handler = handler
        try selectInput(uid: deviceUID)

        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw CaptureError.noInput
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw CaptureError.converter
        }
        self.converter = converter

        let outFormat = self.outFormat
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = outFormat.sampleRate / inFormat.sampleRate
            let outFrames = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else {
                return
            }
            var error: NSError?
            var consumed = false
            converter.convert(to: outBuffer, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return }
            guard let channel = outBuffer.floatChannelData?[0] else { return }
            let count = Int(outBuffer.frameLength)
            if count <= 0 { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            self.handler?(samples)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.engine(error.localizedDescription)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    private func selectInput(uid: String?) throws {
        guard let uid, !uid.isEmpty else { return }
        guard let device = AudioInputs.resolve(uid: uid) else {
            throw CaptureError.deviceMissing(uid)
        }
        _ = engine.inputNode
        engine.prepare()
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw CaptureError.engine("无法访问音频输入单元")
        }
        var deviceID = device.deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw CaptureError.engine("无法使用麦克风「\(device.name)」（错误 \(status)）")
        }
    }

    public func stop() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
        handler = nil
        engine.reset()
    }

    public static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
