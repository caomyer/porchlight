import Foundation
import UIKit

// Opening a recipe's link (docs/design/dishes.md, "Recipes", "Opening a recipe's link"): in
// the app that claims it first, else in the browser. The saved link stays what was pasted.

/// Opens a link in the app that claims it, or in the browser.
@MainActor
protocol RecipeLinkOpening: Sendable {
    /// Opens `url` only if an installed app claims it as a universal link; true when one did.
    func openInApp(_ url: URL) async -> Bool
    func openInBrowser(_ url: URL) async
}

/// One step of a link's redirects.
protocol RecipeLinkRedirects: Sendable {
    /// Where `url` redirects to, or nil when it answers without redirecting.
    func next(after url: URL) async throws -> URL?
}

/// Where a recipe's link was opened.
enum RecipeLinkOutcome: Equatable {
    case app(URL)
    case browser(URL)
}

/// Opens a recipe's link in the app that claims it, following its redirects briefly to find
/// one, and falls back to the browser with the link as it was saved.
///
/// A short link (xhslink.com/o/…) is claimed by no app itself, but redirects to a page
/// (www.xiaohongshu.com/discovery/item/…) that its app does claim. So: the link, upgraded to
/// https, is offered to the apps; then each https hop of its redirects, for a few seconds at
/// most and a few hops at most; then the browser. No per-app list.
@MainActor
struct RecipeLinkOpener {
    var opener: any RecipeLinkOpening
    var redirects: any RecipeLinkRedirects
    /// The whole lookup of redirects, after which the browser opens.
    var budget: Duration = .seconds(3)
    var maxHops = 5
    /// Waits out the budget; a test hands in one that returns at once, or never.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// The saved link with http upgraded to https, which universal links require.
    static func upgraded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = "https"
        return parts.url ?? url
    }

    func open(_ saved: URL) async -> RecipeLinkOutcome {
        let first = Self.upgraded(saved)
        if first.scheme == "https", await opener.openInApp(first) { return .app(first) }
        if let claimed = await claimedHop(from: first) { return .app(claimed) }
        await opener.openInBrowser(saved)
        return .browser(saved)
    }

    /// The first https hop of `url`'s redirects that an app opened, within the budget.
    ///
    /// One hop at a time, each offered to the apps before the next is asked for, so the lookup
    /// stops at the first hop an app takes. The budget bounds only the asking: an offer once
    /// made is always awaited, so an app that takes a hop just as the budget runs out is the
    /// one that opens, and the browser never opens beside it.
    private func claimedHop(from url: URL) async -> URL? {
        let opener = opener, redirects = redirects, maxHops = maxHops, budget = budget, sleep = sleep
        return await withTaskGroup(of: URL?.self) { group in
            group.addTask {
                var current = url
                var seen: Set<URL> = [url]
                for _ in 0..<maxHops {
                    guard let next = try? await redirects.next(after: current) else { return nil }
                    // Once the budget is out, no new offer is made.
                    guard !Task.isCancelled else { return nil }
                    // A loop ends the lookup rather than going round.
                    guard seen.insert(next).inserted else { return nil }
                    // An offer in flight runs to its answer whatever the budget, and counts.
                    if next.scheme?.lowercased() == "https", await opener.openInApp(next) { return next }
                    current = next
                }
                return nil
            }
            group.addTask {
                try? await sleep(budget)
                return nil
            }
            // The first to finish ends the other; a claim from either answer wins.
            var claimed = await group.next() ?? nil
            group.cancelAll()
            for await answer in group where claimed == nil { claimed = answer }
            return claimed
        }
    }
}

// MARK: - The live opener and network

/// Opens through UIKit: universal links only, or the browser.
struct SystemRecipeLinkOpener: RecipeLinkOpening {
    func openInApp(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
    }

    func openInBrowser(_ url: URL) async {
        _ = await UIApplication.shared.open(url)
    }
}

/// Asks the link's own host where it redirects, as Safari on an iPhone would: a GET (some
/// short-link hosts answer HEAD with 404), no cookies, nothing stored, no user data, and no
/// body read beyond the headers.
final class URLSessionRecipeLinkRedirects: NSObject, RecipeLinkRedirects, URLSessionTaskDelegate {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        return URLSession(configuration: configuration)
    }()

    func next(after url: URL) async throws -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        // The headers are all that is needed.
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }

    /// Each hop is looked at in turn, so the session never follows one by itself.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

extension RecipeLinkOpener {
    static var live: RecipeLinkOpener {
        RecipeLinkOpener(opener: SystemRecipeLinkOpener(), redirects: URLSessionRecipeLinkRedirects())
    }
}
