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
        guard let version = AppVersion(release.tag_name),
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.user == nil, release.html_url.password == nil, release.html_url.port == nil,
              release.html_url.path.hasPrefix("/iain-buchan/statsdirect-mac/releases/tag/") else {
            throw failure("GitHub returned an unrecognised release. Check the project's releases page.")
        }
        return version > current ? .available(PublishedUpdate(version: release.tag_name, url: release.html_url)) : .current
    }
    static func check(installed: String, session: URLSession = .shared) async throws -> UpdateStatus {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("StatsDirect-Mac/\(installed)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw failure("GitHub returned an unreadable response.") }
        return try interpret(data, status: response.statusCode, installed: installed)
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "StatsDirect.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
