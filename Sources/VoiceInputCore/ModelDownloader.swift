import Foundation
import CryptoKit

/// 负责从 ModelScope 极速拉取离线 SenseVoice 模型的后台下载与校验器
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = ModelDownloader()

    public static let defaultDownloadURL = URL(
        string: "https://modelscope.cn/api/v1/models/scott887/SenseVoiceSmall-Q8_0.gguf/repo?Revision=master&FilePath=SenseVoiceSmall-Q8_0.gguf"
    )!
    public static let defaultExpectedSHA256 = "6c759ee4c9748c9b3f7a5a60ca74f0f7e685fb9d45d1378fce7cfd62f59adf29"

    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: (@Sendable (Double, String) -> Void)?
    private var expectedBytes: Int64 = 0

    public override init() {
        super.init()
    }

    /// 下载推荐的 SenseVoice 模型并保存至 ~/.transcribe_models/
    @discardableResult
    public func downloadRecommendedModel(
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        let destination = ModelLocator.defaultSharedModelURL()
        return try await download(
            from: Self.defaultDownloadURL,
            to: destination,
            expectedSHA256: Self.defaultExpectedSHA256,
            progress: progress
        )
    }

    /// 从指定 URL 下载模型文件并校验哈希
    public func download(
        from url: URL,
        to destinationURL: URL,
        expectedSHA256: String? = nil,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        self.progressHandler = progress
        self.expectedBytes = 0

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        progress?(0.01, "正在连接 ModelScope 镜像源...")

        let tempURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.continuation = cont
            let task = session.downloadTask(with: url)
            task.resume()
        }

        // 校验完整性
        if let expected = expectedSHA256 {
            progress?(0.99, "正在校验模型完整性 (SHA256)...")
            guard verifyChecksum(fileURL: tempURL, expectedSHA256: expected) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NSError(
                    domain: "ModelDownloader",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "模型校验失败，文件可能已损坏，请重试"]
                )
            }
        }

        // 确保目标父目录存在
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // 移动到目标位置
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        progress?(1.0, "模型就绪")
        return destinationURL
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if expectedBytes <= 0 && totalBytesExpectedToWrite > 0 {
            expectedBytes = totalBytesExpectedToWrite
        }
        let percent: Double
        let totalStr: String
        if expectedBytes > 0 {
            percent = min(0.98, max(0.01, Double(totalBytesWritten) / Double(expectedBytes)))
            totalStr = String(format: "%.1fMB", Double(expectedBytes) / 1024.0 / 1024.0)
        } else {
            percent = 0.5
            totalStr = "约241MB"
        }
        let downloadedStr = String(format: "%.1fMB", Double(totalBytesWritten) / 1024.0 / 1024.0)
        let status = "正在下载 SenseVoice 模型: \(downloadedStr) / \(totalStr) (\(Int(percent * 100))%)"
        progressHandler?(percent, status)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.moveItem(at: location, to: tempDestination)
            continuation?.resume(returning: tempDestination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func verifyChecksum(fileURL: URL, expectedSHA256: String) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        return computed.caseInsensitiveCompare(expectedSHA256) == .orderedSame
    }
}
