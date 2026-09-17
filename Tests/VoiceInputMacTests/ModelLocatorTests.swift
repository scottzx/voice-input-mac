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

    func testUserOverrideWins() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = dir.appendingPathComponent("bundled")
        let customDir = dir.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        let bundledModel = bundled.appendingPathComponent("SenseVoiceSmall-Q8_0.gguf")
        let customModel = customDir.appendingPathComponent("Other-Q8_0.gguf")
        try Data(repeating: 1, count: 2_000_000).write(to: bundledModel)
        try Data(repeating: 2, count: 2_000_000).write(to: customModel)
        let found = ModelLocator.locate(env: [:], home: dir, extraRoots: [bundled], userOverride: customModel)
        XCTAssertEqual(found?.path, customModel.path)
    }

    func testUnusableOverrideFallsBackToBundled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = dir.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let bundledModel = bundled.appendingPathComponent("SenseVoiceSmall-Q8_0.gguf")
        let broken = dir.appendingPathComponent("broken.gguf")
        try Data(repeating: 1, count: 2_000_000).write(to: bundledModel)
        try Data("placeholder\n".utf8).write(to: broken)
        let found = ModelLocator.locate(env: [:], home: dir, extraRoots: [bundled], userOverride: broken)
        XCTAssertEqual(found?.path, bundledModel.path)
    }

    func testFindsSharedTranscribeModels() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sharedDir = dir.appendingPathComponent(".transcribe_models")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let sharedModel = sharedDir.appendingPathComponent("SenseVoiceSmall-Q8_0.gguf")
        try Data(repeating: 1, count: 2_000_000).write(to: sharedModel)
        let found = ModelLocator.locate(env: [:], home: dir)
        XCTAssertEqual(found?.path, sharedModel.path)
    }
}
