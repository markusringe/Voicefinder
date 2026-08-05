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
