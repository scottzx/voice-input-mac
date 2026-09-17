import Foundation
import TranscribeKit

public final class Transcriber: @unchecked Sendable {
    private let engine = StandardTranscriber()

    public var modelPath: String? { engine.loadedModelPath }
    public var backendName: String { engine.backendName }
    public var loaded: Bool { engine.isLoaded }

    public init() {}

    public func load(modelURL: URL) throws {
        try engine.load(modelURL: modelURL)
    }

    public func transcribe(_ pcm: [Float]) throws -> String {
        guard engine.isLoaded else {
            throw TranscriberError.notLoaded
        }
        do {
            let result = try engine.transcribe(pcm: pcm, options: TranscribeOptions(language: nil, itn: true))
            return TextCleanup.transcript(result.rawText)
        } catch {
            throw error
        }
    }

    public func unload() {
        engine.unload()
    }
}

public enum TranscriberError: Error, LocalizedError {
    case notLoaded
    case modelMissing

    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "模型尚未加载"
        case .modelMissing: return "找不到识别模型"
        }
    }
}
