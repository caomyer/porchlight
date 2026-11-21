import Foundation
import Testing
@testable import Porchlight

/// Opening a recipe's link (docs/design/dishes.md, "Opening a recipe's link"): the app that
/// claims the link or one of its redirects, else the browser with the link as saved. The
/// apps and the network are stand-ins; the budget's clock is handed in, so nothing here
/// waits on real time.
@MainActor
@Suite("A recipe's link opens in its app first, then the browser")
struct RecipeLinkTests {
    /// Apps that claim some links, and what was asked of them.
    @MainActor
    final class Apps: RecipeLinkOpening {
        var claims: Set<URL>
        var offered: [URL] = []
        var browser: [URL] = []
        init(claims: Set<URL> = []) { self.claims = claims }
        func openInApp(_ url: URL) async -> Bool {
            offered.append(url)
            return claims.contains(url)
        }
        func openInBrowser(_ url: URL) async { browser.append(url) }
    }

    /// A network that answers from a table of redirects, fails, or never answers.
    final class Network: RecipeLinkRedirects, @unchecked Sendable {
        enum Behavior { case table([URL: URL]), fails, hangs }
        let behavior: Behavior
        private let lock = NSLock()
        private var asked: [URL] = []
        init(_ behavior: Behavior) { self.behavior = behavior }
        var questions: [URL] { lock.withLock { asked } }
        func next(after url: URL) async throws -> URL? {
            lock.withLock { asked.append(url) }
            switch behavior {
            case let .table(table): return table[url]
            case .fails: throw URLError(.notConnectedToInternet)
            case .hangs:
                try await Task.sleep(for: .seconds(3600))
                return nil
            }
        }
    }

    private static let short = URL(string: "http://xhslink.com/o/5sPSVXuNJsQ")!
    private static let shortHTTPS = URL(string: "https://xhslink.com/o/5sPSVXuNJsQ")!
    private static let item = URL(string: "https://www.xiaohongshu.com/discovery/item/abc?xsec=1")!

    /// A budget that never runs out, so only the network decides.
    private static let endless: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

    private func opener(_ apps: Apps, _ network: Network, sleep: @escaping @Sendable (Duration) async throws -> Void = endless) -> RecipeLinkOpener {
        RecipeLinkOpener(opener: apps, redirects: network, sleep: sleep)
    }

    @Test("An app that claims the link itself opens it, with nothing asked of the network")
    func appClaimsTheLink() async {
        let link = URL(string: "https://www.xiaohongshu.com/discovery/item/abc")!
        let apps = Apps(claims: [link]), network = Network(.table([:]))
        #expect(await opener(apps, network).open(link) == .app(link))
        #expect(network.questions.isEmpty)
        #expect(apps.browser.isEmpty)
    }

    @Test("A saved http link is offered to the apps as https, which universal links need")
    func httpIsUpgraded() async {
        let apps = Apps(claims: [Self.shortHTTPS]), network = Network(.table([:]))
        #expect(await opener(apps, network).open(Self.short) == .app(Self.shortHTTPS))
        #expect(apps.offered == [Self.shortHTTPS])
        #expect(RecipeLinkOpener.upgraded(URL(string: "HTTP://a.example/x?y=1#z")!).absoluteString == "https://a.example/x?y=1#z")
        #expect(RecipeLinkOpener.upgraded(URL(string: "https://a.example")!).absoluteString == "https://a.example")
    }

    @Test("An app that claims where a short link redirects opens that page")
    func appClaimsARedirect() async {
        let apps = Apps(claims: [Self.item])
        let network = Network(.table([Self.shortHTTPS: Self.item]))
        #expect(await opener(apps, network).open(Self.short) == .app(Self.item))
        #expect(apps.offered == [Self.shortHTTPS, Self.item])
        #expect(network.questions == [Self.shortHTTPS])
        #expect(apps.browser.isEmpty)
    }

    @Test("An http hop is followed but not offered to the apps; the https hop after it is")
    func httpHopsAreFollowed() async {
        let middle = URL(string: "http://www.xiaohongshu.com/discovery/item/abc")!
        let apps = Apps(claims: [Self.item])
        let network = Network(.table([Self.shortHTTPS: middle, middle: Self.item]))
        #expect(await opener(apps, network).open(Self.short) == .app(Self.item))
        #expect(apps.offered == [Self.shortHTTPS, Self.item])
    }

    @Test("When no app claims the link or its redirects, the browser opens the link as it was saved")
    func nobodyClaims() async {
        let apps = Apps()
        let network = Network(.table([Self.shortHTTPS: Self.item]))
        #expect(await opener(apps, network).open(Self.short) == .browser(Self.short))
        #expect(apps.browser == [Self.short], "the saved http link, not the upgraded one or a hop")
        #expect(network.questions == [Self.shortHTTPS, Self.item])
    }

    @Test("A network that never answers runs out the budget, and the browser opens")
    func timeout() async {
        let apps = Apps(), network = Network(.hangs)
        let outcome = await opener(apps, network, sleep: { _ in }).open(Self.short)
        #expect(outcome == .browser(Self.short))
        #expect(apps.offered == [Self.shortHTTPS])
    }

    @Test("A network error opens the browser")
    func networkError() async {
        let apps = Apps(), network = Network(.fails)
        #expect(await opener(apps, network).open(Self.short) == .browser(Self.short))
        #expect(network.questions == [Self.shortHTTPS])
    }

    @Test("A redirect loop ends at the first repeat, and a long chain at the hop limit")
    func loopsAreBounded() async {
        let a = URL(string: "https://a.example/1")!, b = URL(string: "https://a.example/2")!
        let looping = Network(.table([a: b, b: a]))
        #expect(await opener(Apps(), looping).open(a) == .browser(a))
        #expect(looping.questions == [a, b])

        let chain = (0...20).map { URL(string: "https://a.example/hop/\($0)")! }
        let long = Network(.table(Dictionary(uniqueKeysWithValues: zip(chain, chain.dropFirst()).map { ($0, $1) })))
        let apps = Apps()
        #expect(await opener(apps, long).open(chain[0]) == .browser(chain[0]))
        #expect(long.questions.count == 5, "the hop limit")
        #expect(apps.offered.count == 6, "the link and each of five hops")
    }
}
