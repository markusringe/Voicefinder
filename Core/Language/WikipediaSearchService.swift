//
//  WikipediaSearchService.swift
//  Voicefinder
//
//  Wikipedia-Zusammenfassungen (de) – erste Stufe der Internet-Recherche.
//

import Foundation

/// Liest Kurz-Zusammenfassungen von de.wikipedia.org (REST API, kein API-Key).
struct WikipediaSearchService: Sendable {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    /// Sucht einen passenden Wikipedia-Artikel und liefert den Extract-Text.
    func fetchSummary(for query: String) async throws -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        if let direct = try await fetchPageSummary(title: trimmed) {
            return direct
        }

        if let searchTitle = try await searchTitle(for: trimmed) {
            return try await fetchPageSummary(title: searchTitle)
        }

        return nil
    }

    /// Sucht mit Schlüsselwörtern, holt die ersten Treffer samt Artikelanfang und Suchausschnitten und
    /// liefert die zur Frage passende Passage (siehe `WikipediaPassageSelector`).
    func fetchPassage(for query: WebSearchQuery, maxCharacters: Int) async throws -> String? {
        guard !query.keywords.isEmpty else { return nil }

        async let intros = fetchIntros(terms: query.searchTerms)
        async let snippets = fetchSnippets(terms: query.searchTerms)
        let (introPages, snippetsByTitle) = try await (intros, snippets)

        let pages = introPages.map { page in
            WikipediaPage(
                title: page.title,
                index: page.index,
                intro: page.intro,
                snippets: snippetsByTitle[page.title] ?? []
            )
        }
        return WikipediaPassageSelector.bestPassage(pages: pages, query: query, maxCharacters: maxCharacters)
    }

    /// Artikelanfänge der besten Suchtreffer in einem Aufruf (`generator=search`).
    private func fetchIntros(terms: String) async throws -> [WikipediaPage] {
        var components = URLComponents(string: "https://de.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: terms),
            URLQueryItem(name: "gsrlimit", value: "4"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exlimit", value: "max"),
            URLQueryItem(name: "exchars", value: "1200"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let json = try await requestJSON(components.url) else { return [] }
        guard let queryObject = json["query"] as? [String: Any],
              let pages = queryObject["pages"] as? [String: Any] else { return [] }

        return pages.values.compactMap { value -> WikipediaPage? in
            guard let page = value as? [String: Any],
                  let title = page["title"] as? String,
                  let extract = page["extract"] as? String,
                  !extract.isEmpty else { return nil }
            return WikipediaPage(
                title: title,
                index: page["index"] as? Int ?? 99,
                intro: extract,
                snippets: []
            )
        }
        .sorted { $0.index < $1.index }
    }

    /// Suchausschnitte aus dem Artikeltext – enthalten oft genau den Satz mit der Antwort.
    private func fetchSnippets(terms: String) async throws -> [String: [String]] {
        var components = URLComponents(string: "https://de.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: terms),
            URLQueryItem(name: "srlimit", value: "4"),
            URLQueryItem(name: "srprop", value: "snippet"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let json = try await requestJSON(components.url),
              let queryObject = json["query"] as? [String: Any],
              let results = queryObject["search"] as? [[String: Any]] else { return [:] }

        var byTitle: [String: [String]] = [:]
        for result in results {
            guard let title = result["title"] as? String, let snippet = result["snippet"] as? String else { continue }
            byTitle[title, default: []].append(snippet)
        }
        return byTitle
    }

    private func requestJSON(_ url: URL?) async throws -> [String: Any]? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        // Wikimedia verlangt einen aussagekräftigen User-Agent.
        request.setValue("Voicefinder/1.0 (iOS on-device voice assistant)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Wikipedia REST

    private func fetchPageSummary(title: String) async throws -> String? {
        let encodedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title

        guard let url = URL(string: "https://de.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extract = json["extract"] as? String else {
            return nil
        }

        let cleaned = extract.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Wikipedia-Suche, wenn der direkte Titel nicht passt.
    private func searchTitle(for query: String) async throws -> String? {
        var components = URLComponents(string: "https://de.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "srlimit", value: "1"),
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObject = json["query"] as? [String: Any],
              let searchResults = queryObject["search"] as? [[String: Any]],
              let first = searchResults.first,
              let title = first["title"] as? String else {
            return nil
        }

        return title
    }
}
