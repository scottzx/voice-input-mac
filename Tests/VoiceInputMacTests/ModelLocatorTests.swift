import XCTest
@testable import VoiceInputCore

final class ModelLocatorTests: XCTestCase {
    func testFindsEnvOverride() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = dir.appendingPathComponent("SenseVoiceSmall-Q8_0.gguf")
        try Data(repeating: 1, count: 2_000_000).write(to: model)
        let found = ModelLocator.locate(env: ["VOICE_INPUT_MODEL": model.path], home: dir)
        XCTAssertEqual(found?.path, model.path)
    }

    func testRejectsTinyPlaceholder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = dir.appendingPathComponent("SenseVoiceSmall-Q8_0.gguf")
        try Data("placeholder\n".utf8).write(to: model)
        XCTAssertFalse(ModelLocator.isUsableModel(model))
        let found = ModelLocator.locate(env: ["VOICE_INPUT_MODEL": model.path], home: dir)
        XCTAssertNil(found)
    }
}
