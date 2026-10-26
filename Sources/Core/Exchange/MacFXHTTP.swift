import Foundation

/// A reusable, bounded transport. Delegate callbacks run on a private queue;
/// neither byte accumulation nor response validation occupies the UI actor.
nonisolated final class MacFXHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        var data = Data()
        let continuation: CheckedContinuation<Data, Error>
    }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var session: URLSession!
    static let limit = 2 * 1024 * 1024
    init(protocols: [AnyClass]? = nil) {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 30
        if let protocols { config.protocolClasses = protocols }
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    func invalidate() { session.invalidateAndCancel() }
    private final class Cancellation: @unchecked Sendable {
        let lock = NSLock()
        var task: URLSessionDataTask?
        var cancelled = false
        func start(_ task: URLSessionDataTask) {
            lock.lock(); defer { lock.unlock() }
            self.task = task
            if cancelled { task.cancel() }
            task.resume()
        }
        func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true; task?.cancel() }
    }
    func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let cancellation = Cancellation()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.lock(); pending[task.taskIdentifier] = Pending(continuation: continuation); lock.unlock()
                cancellation.start(task)
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        return data
    }
    private func finish(_ task: URLSessionTask, error: Error?) {
        lock.lock(); let value = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let value else { return }
        if let error { value.continuation.resume(throwing: error) }
        else { value.continuation.resume(returning: value.data) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let error: Error?
        if let http = response as? HTTPURLResponse {
            if !(200..<300).contains(http.statusCode) {
                error = MacFXNetworkFailure.http(http.statusCode, retryAfter: Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
            } else if response.expectedContentLength > Int64(Self.limit) { error = MacFXNetworkFailure.invalid }
            else { error = nil }
        } else { error = MacFXNetworkFailure.invalid }
        if let error { finish(dataTask, error: error); completionHandler(.cancel) }
        else { completionHandler(.allow) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let oversized = (pending[dataTask.taskIdentifier]?.data.count ?? 0) + data.count > Self.limit
        if !oversized { pending[dataTask.taskIdentifier]?.data.append(data) }
        lock.unlock()
        if oversized { finish(dataTask, error: MacFXNetworkFailure.invalid); dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(task, error: error == nil ? nil : MacFXNetworkFailure.unavailable)
    }
    static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
