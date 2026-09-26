import Foundation

struct AppVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct PublishedUpdate {
    let version: String
    let url: URL
}

enum UpdateStatus {
    case available(PublishedUpdate), current, noRelease
}

enum UpdateService {
    static let releases = URL(string: "https://github.com/iain-buchan/statsdirect-mac/releases")!
    static let latestRelease = releases.appendingPathComponent("latest")
    static let endpoint = URL(string: "https://api.github.com/repos/iain-buchan/statsdirect-mac/releases/latest")!
    struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }
    static func interpret(_ data: Data, status: Int, installed: String) throws -> UpdateStatus {
        guard let current = AppVersion(installed) else { throw failure("The installed version could not be read.") }
        if status == 404 { return .noRelease }
        guard status == 200 else {
            throw failure(status == 403 || status == 429 ? "GitHub is limiting update checks. Please try again later." : "GitHub could not be reached successfully (HTTP \(status)). Please try again later.")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return .noRelease }
        guard let version = AppVersion(release.tag_name), isReleaseURL(release.html_url),
              release.html_url.path == releases.path + "/tag/" + release.tag_name else {
            throw failure("GitHub returned an unrecognised release. Check the project's releases page.")
        }
        return version > current ? .available(PublishedUpdate(version: release.tag_name, url: release.html_url)) : .current
    }
    private static func isReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
    }
    // GitHub's documented /releases/latest link redirects to a stable release's tag, or the release list if none exists.
    // Inspect the final URL rather than scraping HTML, which can change or contain a sign-in/error page.
    static func interpretReleasePage(_ response: HTTPURLResponse, installed: String) throws -> UpdateStatus {
        guard let current = AppVersion(installed) else { throw failure("The installed version could not be read.") }
        guard let url = response.url, isReleaseURL(url) else { throw failure("GitHub returned an unrecognised update address.") }
        if response.statusCode == 404 && (url == latestRelease || url == releases) { return .noRelease }
        guard response.statusCode == 200 else { throw failure("GitHub could not complete the update check (HTTP \(response.statusCode)). Please try again later.") }
        if url == releases { return .noRelease }
        let prefix = releases.path + "/tag/"
        guard url.path.hasPrefix(prefix) else { throw failure("GitHub did not return a published release. Please try again later.") }
        let tag = String(url.path.dropFirst(prefix.count))
        guard let version = AppVersion(tag) else { throw failure("GitHub returned an unrecognised release version. Open Downloads to check it.") }
        return version > current ? .available(PublishedUpdate(version: tag, url: url)) : .current
    }
    static func check(installed: String, session: URLSession = .shared) async throws -> UpdateStatus {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("StatsDirect-Mac/\(installed)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw failure("GitHub returned an unreadable response.") }
            return try interpret(data, status: response.statusCode, installed: installed)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
            // Some networks cannot resolve the API host even though the public GitHub site works.
            var fallback = URLRequest(url: latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            fallback.setValue("StatsDirect-Mac/\(installed)", forHTTPHeaderField: "User-Agent")
            fallback.setValue("text/html", forHTTPHeaderField: "Accept")
            let (_, response) = try await session.data(for: fallback)
            guard let response = response as? HTTPURLResponse else { throw failure("GitHub returned an unreadable response.") }
            return try interpretReleasePage(response, installed: installed)
        }
    }
    static func message(for error: Error) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Your Mac could not find GitHub’s update server. Check your internet connection or DNS settings, then try again. You can also open the downloads page in your browser."
            case .notConnectedToInternet:
                return "Your Mac appears to be offline. Reconnect to the internet, then try again."
            case .timedOut, .cannotConnectToHost, .networkConnectionLost:
                return "GitHub could not be reached in time. Check your connection and try again, or open the downloads page in your browser."
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return "A secure connection to GitHub could not be verified. Check your Mac’s date and network connection, then try again."
            default:
                return "StatsDirect could not connect to GitHub to check for updates. Try again later or open the downloads page in your browser."
            }
        }
        return error.localizedDescription
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "StatsDirect.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
