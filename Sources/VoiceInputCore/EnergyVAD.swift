import Foundation

/// Frame-level energy VAD with a slow noise floor, hysteresis, pre-roll, and hangover.
///
/// Call `process` with any-size 16 kHz mono float32 chunks. Completed utterances
/// are returned as events; leftover samples shorter than one frame stay buffered.
public struct EnergyVAD: Sendable {
    public struct Config: Sendable, Equatable {
        public var sampleRate: Int
        public var frameMs: Int
        /// Audio kept before the detected start so the first phoneme is not clipped.
        public var preRollMs: Int
        /// Consecutive speech frames required before a start is committed.
        public var minSpeechMs: Int
        /// Consecutive silence frames required before an utterance ends.
        public var hangoverMs: Int
        /// Hard cut so SenseVoice stays inside its ~30 s window.
        public var maxUtteranceMs: Int
        /// Drop utterances shorter than this after hangover.
        public var minUtteranceMs: Int
        public var startMultiplier: Float
        public var endMultiplier: Float
        public var absStart: Float
        public var absEnd: Float
        public var noiseAttack: Float
        public var noiseRelease: Float

        public init(
            sampleRate: Int = 16_000,
            frameMs: Int = 20,
            preRollMs: Int = 280,
            minSpeechMs: Int = 180,
            hangoverMs: Int = 550,
            maxUtteranceMs: Int = 28_000,
            minUtteranceMs: Int = 280,
            startMultiplier: Float = 3.6,
            endMultiplier: Float = 2.2,
            absStart: Float = 0.012,
            absEnd: Float = 0.006,
            noiseAttack: Float = 0.04,
            noiseRelease: Float = 0.004
        ) {
            self.sampleRate = sampleRate
            self.frameMs = frameMs
            self.preRollMs = preRollMs
            self.minSpeechMs = minSpeechMs
            self.hangoverMs = hangoverMs
            self.maxUtteranceMs = maxUtteranceMs
            self.minUtteranceMs = minUtteranceMs
            self.startMultiplier = startMultiplier
            self.endMultiplier = endMultiplier
            self.absStart = absStart
            self.absEnd = absEnd
            self.noiseAttack = noiseAttack
            self.noiseRelease = noiseRelease
        }

        public var frameSamples: Int { max(1, sampleRate * frameMs / 1000) }
        public var preRollSamples: Int { sampleRate * preRollMs / 1000 }
        public var minSpeechFrames: Int { max(1, minSpeechMs / frameMs) }
        public var hangoverFrames: Int { max(1, hangoverMs / frameMs) }
        public var maxUtteranceSamples: Int { sampleRate * maxUtteranceMs / 1000 }
        public var minUtteranceSamples: Int { sampleRate * minUtteranceMs / 1000 }
    }

    public enum Event: Sendable, Equatable {
        case speechStart
        case speechEnd(pcm: [Float])
        case discardedShort
    }

    public private(set) var config: Config
    public private(set) var inSpeech = false
    public private(set) var noiseFloor: Float = 0.003
    public private(set) var lastRMS: Float = 0

    private var pending: [Float] = []
    private var preRoll: [Float] = []
    private var utterance: [Float] = []
    private var speechRun = 0
    private var silenceRun = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func reset() {
        inSpeech = false
        pending = []
        preRoll = []
        utterance = []
        speechRun = 0
        silenceRun = 0
        lastRMS = 0
    }

    public mutating func updateConfig(_ config: Config) {
        self.config = config
        reset()
    }

    /// Scale start/end multipliers. `sensitivity` 0...1, default 0.55.
    public mutating func setSensitivity(_ sensitivity: Float) {
        let s = min(1, max(0, sensitivity))
        var next = config
        next.startMultiplier = 5.2 - 3.0 * s
        next.endMultiplier = 3.2 - 1.8 * s
        next.absStart = 0.020 - 0.014 * s
        next.absEnd = 0.010 - 0.007 * s
        updateConfig(next)
    }

    public mutating func process(_ samples: [Float]) -> [Event] {
        if samples.isEmpty { return [] }
        pending.append(contentsOf: samples)
        var events: [Event] = []
        let frame = config.frameSamples
        while pending.count >= frame {
            let frameSamples = Array(pending.prefix(frame))
            pending.removeFirst(frame)
            if let event = consumeFrame(frameSamples) {
                events.append(event)
            }
        }
        return events
    }

    /// Flush a trailing in-progress utterance (user stopped listening).
    public mutating func flush() -> Event? {
        pending = []
        speechRun = 0
        silenceRun = 0
        guard inSpeech else {
            utterance = []
            return nil
        }
        inSpeech = false
        let pcm = utterance
        utterance = []
        if pcm.count < config.minUtteranceSamples {
            return .discardedShort
        }
        return .speechEnd(pcm: pcm)
    }

    private mutating func consumeFrame(_ frame: [Float]) -> Event? {
        let rms = Self.rms(frame)
        lastRMS = rms
        let startGate = max(config.absStart, noiseFloor * config.startMultiplier)
        let endGate = max(config.absEnd, noiseFloor * config.endMultiplier)
        let voiced = rms >= (inSpeech ? endGate : startGate)

        if !inSpeech {
            updateNoise(rms)
            appendPreRoll(frame)
            if voiced {
                speechRun += 1
            } else {
                speechRun = 0
            }
            if speechRun >= config.minSpeechFrames {
                inSpeech = true
                silenceRun = 0
                speechRun = 0
                utterance = preRoll
                utterance.append(contentsOf: frame)
                preRoll = []
                return .speechStart
            }
            return nil
        }

        utterance.append(contentsOf: frame)
        if voiced {
            silenceRun = 0
        } else {
            silenceRun += 1
            updateNoise(rms)
        }

        if utterance.count >= config.maxUtteranceSamples {
            return finishUtterance()
        }
        if silenceRun >= config.hangoverFrames {
            return finishUtterance()
        }
        return nil
    }

    private mutating func finishUtterance() -> Event {
        inSpeech = false
        speechRun = 0
        silenceRun = 0
        let hangoverSamples = min(utterance.count, config.hangoverFrames * config.frameSamples)
        // Keep a little hangover so plosives at the end survive, but drop long tail silence.
        let keepHangover = min(hangoverSamples, config.sampleRate * 180 / 1000)
        let cut = max(0, utterance.count - hangoverSamples + keepHangover)
        let pcm = Array(utterance.prefix(cut))
        utterance = []
        preRoll = []
        if pcm.count < config.minUtteranceSamples {
            return .discardedShort
        }
        return .speechEnd(pcm: pcm)
    }

    private mutating func appendPreRoll(_ frame: [Float]) {
        preRoll.append(contentsOf: frame)
        let overflow = preRoll.count - config.preRollSamples
        if overflow > 0 {
            preRoll.removeFirst(overflow)
        }
    }

    private mutating func updateNoise(_ rms: Float) {
        let alpha = rms > noiseFloor ? config.noiseRelease : config.noiseAttack
        noiseFloor = noiseFloor + alpha * (rms - noiseFloor)
        noiseFloor = min(max(noiseFloor, 0.0004), 0.05)
    }

    public static func rms(_ samples: [Float]) -> Float {
        if samples.isEmpty { return 0 }
        var sum: Float = 0
        for s in samples {
            sum += s * s
        }
        return sqrt(sum / Float(samples.count))
    }
}
