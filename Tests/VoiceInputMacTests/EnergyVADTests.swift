import XCTest
@testable import VoiceInputCore

final class EnergyVADTests: XCTestCase {
    func testSilenceDoesNotStart() {
        var vad = EnergyVAD()
        let silence = [Float](repeating: 0, count: 16_000)
        let events = vad.process(silence)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(vad.inSpeech)
    }

    func testSpeechThenSilenceEmitsUtterance() {
        var config = EnergyVAD.Config()
        config.hangoverMs = 200
        config.minSpeechMs = 80
        config.minUtteranceMs = 80
        config.preRollMs = 40
        config.absStart = 0.02
        config.absEnd = 0.01
        var vad = EnergyVAD(config: config)

        let tone = sine(hz: 220, seconds: 0.6, amplitude: 0.2)
        let gap = [Float](repeating: 0, count: 16_000 / 2)
        var events = vad.process(tone)
        events.append(contentsOf: vad.process(gap))

        let ends = events.compactMap { event -> [Float]? in
            if case .speechEnd(let pcm) = event { return pcm }
            return nil
        }
        XCTAssertEqual(ends.count, 1)
        XCTAssertGreaterThan(ends[0].count, 16_000 / 10)
        XCTAssertFalse(vad.inSpeech)
    }

    func testShortBlipIsDiscarded() {
        var config = EnergyVAD.Config()
        config.minSpeechMs = 20
        config.minUtteranceMs = 400
        config.hangoverMs = 80
        config.absStart = 0.02
        var vad = EnergyVAD(config: config)
        let blip = sine(hz: 440, seconds: 0.04, amplitude: 0.3)
        let gap = [Float](repeating: 0, count: 8_000)
        let events = vad.process(blip + gap)
        XCTAssertTrue(events.contains(.discardedShort) || events.isEmpty)
        XCTAssertFalse(events.contains { if case .speechEnd = $0 { return true }; return false })
    }

    func testFlushEndsOpenUtterance() {
        var vad = EnergyVAD()
        _ = vad.process(sine(hz: 180, seconds: 0.8, amplitude: 0.25))
        XCTAssertTrue(vad.inSpeech)
        let event = vad.flush()
        guard case .speechEnd(let pcm)? = event else {
            return XCTFail("expected speechEnd, got \(String(describing: event))")
        }
        XCTAssertGreaterThan(pcm.count, 1000)
        XCTAssertFalse(vad.inSpeech)
    }

    private func sine(hz: Float, seconds: Double, amplitude: Float) -> [Float] {
        let n = Int(16_000 * seconds)
        let omega = 2 * Float.pi * hz / 16_000
        return (0..<n).map { i in amplitude * sin(omega * Float(i)) }
    }
}
