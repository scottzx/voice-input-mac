import XCTest
@testable import VoiceInputCore

final class TextCleanupTests: XCTestCase {
    func testStripsSenseVoiceTags() {
        let raw = "<|zh|><|NEUTRAL|><|Speech|>今天天气不错"
        XCTAssertEqual(TextCleanup.transcript(raw), "今天天气不错")
    }

    func testCJKGlueHasNoSpace() {
        XCTAssertEqual(TextCleanup.glue(previous: "今天", incoming: "天气"), "")
    }

    func testLatinGlueHasSpace() {
        XCTAssertEqual(TextCleanup.glue(previous: "hello", incoming: "world"), " ")
    }

    func testUselessPunctuation() {
        XCTAssertFalse(TextCleanup.isUseful("…"))
        XCTAssertFalse(TextCleanup.isUseful("   "))
        XCTAssertTrue(TextCleanup.isUseful("你好"))
    }
}
