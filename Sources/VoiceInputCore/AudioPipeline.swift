import Foundation

/// Owns the energy VAD. All methods hop onto `queue`; callers never touch `EnergyVAD` directly.
public final class AudioPipeline: @unchecked Sendable {
    public struct Snapshot: Sendable {
        public var events: [EnergyVAD.Event]
        public var rms: Float
        public var inSpeech: Bool
    }

    public let queue = DispatchQueue(label: "voice.input.audio")
    private var vad = EnergyVAD()

    public init() {}

    public func setSensitivity(_ value: Float) {
        queue.async { self.vad.setSensitivity(value) }
    }

    public func reset() {
        queue.async { self.vad.reset() }
    }

    public func process(_ samples: [Float], then: @escaping (Snapshot) -> Void) {
        queue.async {
            let events = self.vad.process(samples)
            then(Snapshot(events: events, rms: self.vad.lastRMS, inSpeech: self.vad.inSpeech))
        }
    }

    public func flush(then: @escaping (EnergyVAD.Event?) -> Void) {
        queue.async {
            then(self.vad.flush())
        }
    }
}
