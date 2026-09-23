import XCTest
@testable import VoiceInputCore

final class TextInserterTests: XCTestCase {
    func testUnsupportedAXUsesClipboardForWebEditor() {
        let text = "识别后的问题 👋\n第二行"
        var pasted: [String] = []
        XCTAssertTrue(TextInserter.insert(text, isTrusted: true, viaAX: { _ in false }, viaClipboard: {
            pasted.append($0)
            return true
        }))
        XCTAssertEqual(pasted, [text])
    }

    func testWebEditorUsesPasteEvenWhenAXWouldReportSuccess() {
        var pasted: [String] = []
        XCTAssertTrue(TextInserter.insert("网页输入测试", isTrusted: true, viaAX: { _ in
            XCTFail("网页 AX 的成功返回不能证明文字已插入")
            return true
        }, viaClipboard: {
            pasted.append($0)
            return true
        }))
        XCTAssertEqual(pasted, ["网页输入测试"])
    }

    func testFailedPasteRequestFallsBackToAX() {
        var calls: [String] = []
        XCTAssertTrue(TextInserter.insert("你好", isTrusted: true, viaAX: { _ in
            calls.append("AX")
            return true
        }, viaClipboard: { _ in
            calls.append("paste")
            return false
        }))
        XCTAssertEqual(calls, ["paste", "AX"])
    }

    func testClipboardFailureIsReported() {
        XCTAssertFalse(TextInserter.insert("你好", isTrusted: true, viaAX: { _ in false }, viaClipboard: { _ in false }))
    }

    func testNoPermissionDoesNotAttemptInsertion() {
        XCTAssertFalse(TextInserter.insert("你好", isTrusted: false, viaAX: { _ in
            XCTFail("没有辅助功能权限")
            return true
        }, viaClipboard: { _ in
            XCTFail("没有辅助功能权限")
            return true
        }))
    }

    func testEmptyTextDoesNotAttemptInsertion() {
        XCTAssertTrue(TextInserter.insert("", isTrusted: false, viaAX: { _ in
            XCTFail("空文本无需写入")
            return false
        }, viaClipboard: { _ in
            XCTFail("空文本无需粘贴")
            return false
        }))
    }
}
