import XCTest
@testable import VoiceInputCore

final class TextPolisherTests: XCTestCase {
    func testStripsThinkBlock() {
        let raw = "<think>\n让用户用编译来测试。\n</think>这个功能要怎么测试？我们编译一下，看一下效果怎么样。"
        XCTAssertEqual(
            TextPolisher.stripReasoningBlocks(in: raw),
            "这个功能要怎么测试？我们编译一下，看一下效果怎么样。"
        )
    }

    func testStripsThinkingWithAttributes() {
        let raw = "<thinking lang=\"en\">analysis</thinking>这是整理后的文本。"
        XCTAssertEqual(
            TextPolisher.stripReasoningBlocks(in: raw),
            "这是整理后的文本。"
        )
    }

    func testStripsMultipleBlocksAndVariants() {
        let raw = "<think>first</think>A。<reason>second</reason>B。prefix<analysis>x</analysis>tail"
        XCTAssertEqual(
            TextPolisher.stripReasoningBlocks(in: raw),
            "A。B。prefixtail"
        )
    }

    func testLeavesContentWithoutTagsAlone() {
        let raw = "没有任何标签的整理结果。"
        XCTAssertEqual(
            TextPolisher.stripReasoningBlocks(in: raw),
            "没有任何标签的整理结果。"
        )
    }

    func testStripsUnclosedThinkBlock() {
        let raw = "<think>\n思考到一半被截断的内容\n没有结束标签"
        XCTAssertEqual(
            TextPolisher.stripReasoningBlocks(in: raw),
            ""
        )
    }
}