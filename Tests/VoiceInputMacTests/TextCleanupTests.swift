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
        XCTAssertFalse(TextCleanup.isUseful(TextCleanup.transcript("嗯，")))
    }

    func testLocalDictationFillers() {
        XCTAssertEqual(
            TextCleanup.transcript("嗯，我们现在考虑啊就是说增加一些。"),
            "我们现在考虑增加一些。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("做这个云输入的时候。"),
            "做这个云输入的时候。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("会有一些口水词嘛。"),
            "会有一些口水词。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("口水池这些口水词是不是引入大模型做修正物比较好？"),
            "口水池这些口水词是不是引入大模型做修正物比较好？"
        )
        XCTAssertEqual(
            TextCleanup.transcript("嗯，你可以看到我们目前。"),
            "你可以看到我们目前。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("我们已经在本地做了一些测试了。"),
            "我们已经在本地做了一些测试了。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("嗯，然后你可以看一下啊，就是说那针对我们本地的测试。"),
            "然后你可以看一下，针对我们本地的测试。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("说有就是说有没有一些内容是可以去。"),
            "有没有一些内容是可以去。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("添加使用的。"),
            "添加使用的。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("你可以看一下我们的日志，就是说我们这些内容的话嗯。"),
            "你可以看一下我们的日志，我们这些内容。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("基于一些这种比较确定性的规则。"),
            "基于一些比较确定性的规则。"
        )
        XCTAssertEqual(
            TextCleanup.transcript("嗯，怎么去做一些删除跟修改？"),
            "怎么去做一些删除跟修改？"
        )
    }

    func testKeepsContentLookalikes() {
        XCTAssertEqual(TextCleanup.transcript("把那个文件打开"), "把那个文件打开")
        XCTAssertEqual(TextCleanup.transcript("也就是说我们可以开始"), "也就是说我们可以开始")
        XCTAssertEqual(TextCleanup.transcript("如果你方便的话就现在开始"), "如果你方便的话就现在开始")
        XCTAssertEqual(TextCleanup.transcript("这个这个文件"), "这个文件")
    }
}
