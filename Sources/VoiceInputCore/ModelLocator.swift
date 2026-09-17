import Foundation

public enum ModelLocator {
    public static let defaultFileName = "SenseVoiceSmall-Q8_0.gguf"

    public static func locate(
        fileName: String = defaultFileName,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraRoots: [URL] = [],
        userOverride: URL? = nil
    ) -> URL? {
        if let userOverride, isUsableModel(userOverride) {
            return userOverride.standardizedFileURL
        }
        if let override = env["VOICE_INPUT_MODEL"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            return isUsableModel(url) ? url.standardizedFileURL : nil
        }
        var candidates: [URL] = extraRoots.map { $0.appendingPathComponent(fileName) }
        candidates.append(contentsOf: [
            home.appendingPathComponent(".transcribe_models/\(fileName)"),
            home.appendingPathComponent("Library/Application Support/VoiceInputMac/models/\(fileName)"),
            home.appendingPathComponent(".voice_input_mac/models/\(fileName)"),
            home.appendingPathComponent(".1agents/models/\(fileName)"),
        ])
        if let transcribe = env["TRANSCRIBE_CPP"], !transcribe.isEmpty {
            candidates.append(URL(fileURLWithPath: transcribe).appendingPathComponent("models/\(fileName)"))
        }
        candidates.append(contentsOf: defaultTranscribeRoots(home: home).map {
            $0.appendingPathComponent("models/\(fileName)")
        })

        let fm = FileManager.default
        var seen = Set<String>()
        for url in candidates {
            let path = url.standardizedFileURL.path
            if seen.contains(path) { continue }
            seen.insert(path)
            if isUsableModel(url, fm: fm) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    public static func bundledModelsDirectory(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("models")
    }

    public static func defaultSharedDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".transcribe_models")
    }

    public static func defaultSharedModelURL(
        fileName: String = defaultFileName,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        defaultSharedDirectory(home: home).appendingPathComponent(fileName)
    }

    public static func isUsableModel(_ url: URL, fm: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        // Real GGUF weights are tens of MB; skip broken 29-byte placeholder files.
        return size.int64Value > 1_000_000
    }

    public static func defaultTranscribeRoots(home: URL) -> [URL] {
        let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [
            here.appendingPathComponent("vendor/transcribe.cpp"),
            here.appendingPathComponent("../../1agents_app/reference_repo/transcribe.cpp"),
            home.appendingPathComponent("Documents/01-开发项目/1agents/1agents_app/reference_repo/transcribe.cpp"),
        ]
    }
}
