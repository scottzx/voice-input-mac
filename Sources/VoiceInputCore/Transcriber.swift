import Foundation
import TranscribeCpp

public final class Transcriber: @unchecked Sendable {
    public private(set) var modelPath: String?
    public private(set) var backendName: String = ""
    public private(set) var loaded = false

    private var model: Model?
    private var session: Session?
    private let lock = NSLock()
    private let runOptions = RunOptions(itn: .on, language: nil)

    public init() {}

    public func load(modelURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let path = modelURL.path
        if loaded, modelPath == path, session != nil {
            return
        }
        model = nil
        session = nil
        loaded = false
        let loadedModel = try Model(path: path, options: ModelOptions(backend: .auto))
        let loadedSession = try loadedModel.session()
        model = loadedModel
        session = loadedSession
        modelPath = path
        backendName = loadedModel.backend
        loaded = true
    }

    public func transcribe(_ pcm: [Float]) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let session else {
            throw TranscriberError.notLoaded
        }
        let transcript = try session.run(pcm, options: runOptions)
        return TextCleanup.transcript(transcript.text)
    }

    public func unload() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
        model = nil
        loaded = false
        backendName = ""
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
