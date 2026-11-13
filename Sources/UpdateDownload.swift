import Foundation
import CryptoKit

extension UpdateArchive {
    func download(to directory: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        try Task.checkCancellation()
        let parts = url.pathComponents
        guard parts.count == 7, Self.canonicalURL(tag: parts[5])?.absoluteString == url.absoluteString,
              size > 0, size <= Self.maximumSize, Self.isSHA256(sha256), directory.isFileURL else {
            throw UpdateService.failure("The update download does not have verified release metadata.")
        }

        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = directory.appendingPathComponent(".update-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var verified = false
        defer { if !verified { try? manager.removeItem(at: staging) } }

        let destination = staging.appendingPathComponent(url.lastPathComponent)
        guard manager.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw UpdateService.failure("StatsDirect could not save the update download.")
        }
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        do {
            try await UpdateArchiveTransfer(archive: self, file: file).fetch(configuration: configuration)
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try file.close()
        try Task.checkCancellation()
        verified = true
        return destination
    }

    fileprivate func permitsDownloadURL(_ candidate: URL?) -> Bool {
        guard let candidate else { return false }
        if candidate.absoluteString == url.absoluteString { return true }
        guard candidate.scheme == "https", candidate.user == nil, candidate.password == nil,
              candidate.port == nil, candidate.fragment == nil, !candidate.pathComponents.contains("..") else { return false }
        // GitHub redirects release archives to signed URLs on its release asset CDN.
        return (candidate.host == "release-assets.githubusercontent.com" && candidate.path.hasPrefix("/github-production-release-asset/"))
            || (candidate.host == "objects.githubusercontent.com" && candidate.path.hasPrefix("/github-production-release-asset-"))
    }
}

private final class UpdateArchiveTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let archive: UpdateArchive
    private let file: FileHandle
    // Transfer state is accessed on the serial delegate queue. Cancellation may
    // arrive before the task exists, so registration and cancellation share a lock.
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelled = false
    private var acceptedResponse = false
    private var redirects = 0
    private var received: Int64 = 0
    private var digest = SHA256()
    private var failure: Error?
    private var finished = false

    init(archive: UpdateArchive, file: FileHandle) {
        self.archive = archive
        self.file = file
    }

    func fetch(configuration: URLSessionConfiguration) async throws {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 1800
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: archive.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("StatsDirect-Mac-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
                let task = session.dataTask(with: request)
                let started = lock.withLock {
                    guard !cancelled else { return false }
                    self.task = task
                    continuation = completion
                    return true
                }
                if started { task.resume() }
                else { completion.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let task = self.lock.withLock {
                self.cancelled = true
                return self.task
            }
            // Complete on the delegate queue so cancellation is ordered after
            // any active file write, even if the session never calls back.
            queue.addOperation {
                self.finish(.failure(CancellationError()))
                task?.cancel()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard !finished, redirects <= 3, archive.permitsDownloadURL(request.url) else {
            failure = UpdateService.failure("The update download redirects outside GitHub's release servers.")
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished, failure == nil else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, archive.permitsDownloadURL(http.url) else {
            failure = UpdateService.failure("The update download did not return a valid response from GitHub.")
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength == archive.size else {
            failure = UpdateService.failure("The update download size does not match the published release.")
            completionHandler(.cancel)
            return
        }
        acceptedResponse = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, failure == nil, acceptedResponse else { return }
        guard Int64(data.count) <= archive.size - received else {
            failure = UpdateService.failure("The update download exceeds the published size.")
            dataTask.cancel()
            return
        }
        do {
            try file.write(contentsOf: data)
            digest.update(data: data)
            received += Int64(data.count)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        let result = Result<Void, Error> {
            if let error = failure ?? error { throw error }
            guard acceptedResponse, received == archive.size else {
                throw UpdateService.failure("The update download size does not match the published release.")
            }
            let sha256 = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard sha256 == archive.sha256.lowercased() else {
                throw UpdateService.failure("The update download checksum does not match the published release.")
            }
        }
        finish(result)
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        let completion = lock.withLock {
            let completion = continuation
            continuation = nil
            self.task = nil
            return completion
        }
        completion?.resume(with: result)
    }
}
