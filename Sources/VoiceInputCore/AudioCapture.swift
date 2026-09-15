import AVFoundation
import Foundation

public final class AudioCapture {
    public static let sampleRate: Double = 16_000

    public enum CaptureError: Error, LocalizedError {
        case noInput
        case converter
        case engine(String)

        public var errorDescription: String? {
            switch self {
            case .noInput: return "没有可用的麦克风"
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

    public init() {
        outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    public var isRunning: Bool { engine.isRunning }

    public func start(handler: @escaping ([Float]) -> Void) throws {
        stop()
        self.handler = handler

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
    }

    public func stop() {
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
