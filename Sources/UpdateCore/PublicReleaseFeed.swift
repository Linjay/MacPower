import Foundation

/// Atom supplies versions and notes; the release header supplies GitHub's channel flag.
/// A plain version tag can still be a preview, so neither its title nor SemVer is sufficient.
struct PublicReleaseEntry {
    let tag: String
    let version: ReleaseVersion
    let notes: String
}

final class PublicReleaseFeed: NSObject, XMLParserDelegate {
    private var elements: [String] = []
    private var feedID = ""
    private var link: String?
    private var content = ""
    private var entryCount = 0
    private var validFeed = false
    private(set) var entries: [PublicReleaseEntry] = []

    static func parse(_ data: Data) throws -> [PublicReleaseEntry] {
        guard data.count <= 4_000_000 else { throw UpdateError.invalidResponse }
        let delegate = PublicReleaseFeed()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.validFeed,
              delegate.feedID == "tag:github.com,2008:https://github.com/Linjay/MacPower/releases",
              delegate.entryCount == 0 || !delegate.entries.isEmpty else { throw UpdateError.invalidResponse }
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elements.append(elementName)
        if elements == ["feed"] { validFeed = namespaceURI == "http://www.w3.org/2005/Atom" }
        if elements == ["feed", "entry"] { entryCount += 1; link = nil; content = "" }
        if elements == ["feed", "entry", "link"], attributes["rel"] == "alternate" { link = attributes["href"] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if elements == ["feed", "id"] { feedID += string }
        if elements == ["feed", "entry", "content"] { content += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elements == ["feed", "entry"], let link, let url = URL(string: link),
           url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
           url.query == nil, url.fragment == nil, url.pathComponents.count == 6,
           url.pathComponents.prefix(5).elementsEqual(["/", "Linjay", "MacPower", "releases", "tag"]),
           let version = ReleaseVersion(url.lastPathComponent) {
            let notes = content.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(PublicReleaseEntry(tag: url.lastPathComponent, version: version, notes: String(notes.prefix(16_000))))
        }
        elements.removeLast()
    }

    static func isPreview(page: Data, tag: String) throws -> Bool {
        guard page.count <= 4_000_000, let html = String(data: page, encoding: .utf8),
              html.contains("src=\"\(ReleaseClient.releasesURL.appendingPathComponent("expanded_assets").appendingPathComponent(tag).absoluteString)\""),
              let heading = html.range(of: "<h1\\b[^>]*data-view-component=\"true\"[^>]*>", options: .regularExpression),
              let end = html.range(of: "<select-panel", range: heading.upperBound..<html.endIndex),
              html.range(of: "data-test-selector=\"body-content\"", range: heading.upperBound..<end.lowerBound) == nil else {
            throw UpdateError.invalidResponse
        }
        let header = String(html[heading.lowerBound..<end.lowerBound])
        return header.range(of: "<span\\b[^>]*class=\"[^\"]*\\bLabel\\b[^\"]*\"[^>]*>\\s*Pre-release\\s*</span>", options: .regularExpression) != nil
    }

    static func downloadURL(assets: Data, tag: String, version: ReleaseVersion, architecture: String) throws -> URL? {
        guard assets.count <= 4_000_000, let html = String(data: assets, encoding: .utf8),
              html.range(of: "<div\\b[^>]*class=\"[^\"]*\\bBox\\b[^\"]*\"", options: .regularExpression) != nil else {
            throw UpdateError.invalidResponse
        }
        let url = ReleaseClient.releasesURL.appendingPathComponent("download").appendingPathComponent(tag)
            .appendingPathComponent("MacPower-\(version.number)-\(architecture).zip")
        let path = NSRegularExpression.escapedPattern(for: url.path)
        // Only an actual asset link qualifies; mentioning the filename in release notes does not.
        return html.range(of: "<a\\b[^>]*href=\"\(path)\"[^>]*>", options: .regularExpression) == nil ? nil : url
    }
}
