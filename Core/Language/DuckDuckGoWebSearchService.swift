//
//  DuckDuckGoWebSearchService.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Fehler bei der DuckDuckGo-Instant-Answer-Suche.
enum WebSearchError: LocalizedError, Sendable {
    case invalidQuery
    case invalidResponse
    case emptyResults
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            "Suchanfrage ist leer."
        case .invalidResponse:
            "Web-Antwort konnte nicht gelesen werden."
        case .emptyResults:
            "Keine passenden Web-Ergebnisse gefunden."
        case .timedOut:
            "Die Web-Recherche hat zu lange gedauert."
        }
    }
}

/// On-Device-initiierte Websuche über DuckDuckGo (HTTPS, kein API-Key).
///
/// Struct statt Actor: nur immutable `URLSession`, kein geteilter Zustand.
/// Instanzierung erfolgt auf dem MainActor (siehe `AppDependencies`), weil `URLSession(...)` in Swift 6 MainActor-isoliert ist.
struct DuckDuckGoWebSearchService: WebSearchProviding, Sendable {
    private let session: URLSession

    /// Eigenes URLSession-Objekt statt `.shared` (`.shared` ist MainActor-isoliert in Swift 6).
    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func fetchContext(for query: String) async throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { throw WebSearchError.invalidQuery }

        guard let instant = try await fetchInstantAnswer(for: trimmed) else {
            throw WebSearchError.emptyResults
        }

        return instant
    }

    // MARK: - DuckDuckGo Instant Answer

    private func fetchInstantAnswer(for query: String) async throws -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]

        guard let url = components.url else { throw WebSearchError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw WebSearchError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSearchError.invalidResponse
        }

        var snippets: [String] = []

        if let abstract = json["AbstractText"] as? String {
            let trimmed = abstract.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let source = (json["AbstractSource"] as? String) ?? "Web"
                snippets.append("\(source): \(trimmed)")
            }
        }

        if let related = json["RelatedTopics"] as? [Any] {
            for item in related.prefix(5) {
                if let topic = item as? [String: Any],
                   let text = topic["Text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { snippets.append(trimmed) }
                }
            }
        }

        guard !snippets.isEmpty else { return nil }
        return "DuckDuckGo:\n" + snippets.joined(separator: "\n")
    }
}
