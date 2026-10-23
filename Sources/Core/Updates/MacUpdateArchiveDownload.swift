import Foundation
import CryptoKit

/// A disk-backed transfer. Delegate callbacks stay on URLSession's serial queue;
/// the lock covers cancellation arriving from the calling task.
nonisolated final class MacUpdateArchiveDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let limit: Int64
    private let progress: @Sendable (Int) -> Void
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var failure: Error?
    private var cancelled = false
    private var completedFile = false
    private var lastPercent = -1

    init(destination: URL, limit: Int64, progress: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.destination = destination
        self.limit = limit
        self.progress = progress
    }

    func download(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        try Task.checkCancellation()
        guard MacUpdateService.validatedURL(url.absoluteString) != nil else { throw MacUpdateTransferError.invalidResponse }
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("FinTrack", forHTTPHeaderField: "User-Agent")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                let cancelled = lock.withLock {
                    self.continuation = continuation
                    self.task = task
                    return self.cancelled
                }
                task.resume()
                if cancelled { task.cancel() }
            }
        } onCancel: {
            let task = self.lock.withLock { self.cancelled = true; return self.task }
            task?.cancel()
        }
    }

    static func validate(_ response: URLResponse?, received: Int64, limit: Int64) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = http.url, MacUpdateService.validatedURL(url.absoluteString) != nil else {
            throw MacUpdateTransferError.invalidResponse
        }
        guard received <= limit, http.expectedContentLength <= limit else { throw MacUpdateTransferError.tooLarge }
    }

    static func verify(_ file: URL, sha256: String) async throws {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == sha256 else { throw MacUpdateTransferError.checksumMismatch }
        }.value
        try Task.checkCancellation()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, MacUpdateService.validatedURL(url.absoluteString) != nil else {
            lock.withLock { failure = MacUpdateTransferError.invalidResponse }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        do {
            try Self.validate(downloadTask.response, received: totalBytesWritten, limit: limit)
            if totalBytesExpectedToWrite > 0 {
                let percent = min(100, Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100))
                let changed = lock.withLock { () -> Bool in
                    guard percent > lastPercent else { return false }
                    lastPercent = percent
                    return true
                }
                if changed { progress(percent) }
            }
        } catch {
            lock.withLock { failure = error }
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? Int64.max
            try Self.validate(downloadTask.response, received: size, limit: limit)
            try FileManager.default.moveItem(at: location, to: destination)
            lock.withLock { completedFile = true }
        } catch { lock.withLock { failure = error } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = lock.withLock { () -> (CheckedContinuation<URL, Error>?, Error?) in
            let result = (continuation, failure ?? error ?? (completedFile ? nil : MacUpdateTransferError.invalidResponse))
            continuation = nil
            self.task = nil
            return result
        }
        if let error = result.1 {
            try? FileManager.default.removeItem(at: destination)
            result.0?.resume(throwing: error)
        } else { result.0?.resume(returning: destination) }
    }
}

nonisolated enum MacUpdateTransferError: LocalizedError {
    case invalidResponse, tooLarge, checksumMismatch
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "更新服务器响应无效，或下载链接不安全"
        case .tooLarge: return "更新文件超过大小限制，已停止下载"
        case .checksumMismatch: return "安装包校验不一致，已拒绝安装"
        }
    }
}
