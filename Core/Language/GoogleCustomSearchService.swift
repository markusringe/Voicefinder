//
//  GoogleCustomSearchService.swift
//  Voicefinder
//
//  Websuche über die offizielle Google Custom Search JSON API.
//

import Foundation

/// Fehler speziell für die Google-Suche.
enum GoogleSearchError: LocalizedError, Sendable {
    case notConfigured
    case invalidQuery
    case invalidResponse
    case emptyResults
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Google-Suche ist nicht konfiguriert (API-Schlüssel und Suchmaschinen-ID fehlen)."
        case .invalidQuery:
            "Suchanfrage ist leer."
        case .invalidResponse:
            "Google-Antwort konnte nicht gelesen werden."
        case .emptyResults:
            "Google lieferte keine passenden Treffer."
        case .quotaExceeded:
            "Google-Suchkontingent erschöpft – Fallback wird genutzt."
        }
    }
}

/// Primäre Websuche über Google Programmable Search (Custom Search JSON API).
///
/// Voraussetzung: API-Schlüssel + Suchmaschinen-ID (cx) in den Einstellungen oder Info.plist.
/// Dokumentation: https://developers.google.com/custom-search/v1/overview
struct GoogleCustomSearchService: WebSearchProviding, Sendable {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    /// True, wenn API-Schlüssel und cx gesetzt sind.
    nonisolated var isConfigured: Bool {
        AppSettingsStore.isGoogleSearchConfigured
    }

    func fetchContext(for query: String) async throws -> String {
        guard isConfigured else { throw GoogleSearchError.notConfigured }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { throw GoogleSearchError.invalidQuery }

        let apiKey = AppSettingsStore.googleSearchAPIKey
        let engineID = AppSettingsStore.googleSearchEngineID

        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: engineID),
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "hl", value: "de"),
            URLQueryItem(name: "gl", value: "de"),
            URLQueryItem(name: "num", value: "5"),
        ]

        guard let url = components.url else { throw GoogleSearchError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleSearchError.invalidResponse
        }

        if http.statusCode == 429 {
            throw GoogleSearchError.quotaExceeded
        }

        guard (200 ... 299).contains(http.statusCode) else {
            if let apiError = parseAPIError(from: data) {
                NSLog("[Voicefinder] Google-Suche HTTP %d: %@", http.statusCode, apiError)
            }
            throw GoogleSearchError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleSearchError.invalidResponse
        }

        let snippets = extractSnippets(from: json)
        guard !snippets.isEmpty else { throw GoogleSearchError.emptyResults }

        return "Google:\n" + snippets.joined(separator: "\n")
    }

    /// Liest Titel und Snippets der Top-Treffer für das LLM.
    private func extractSnippets(from json: [String: Any]) -> [String] {
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        return items.prefix(5).compactMap { item in
            let title = (item["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = (item["snippet"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !snippet.isEmpty else { return nil }

            if title.isEmpty {
                return snippet
            }
            return "• \(title): \(snippet)"
        }
    }

    /// Versucht, eine lesbare Fehlermeldung aus der Google-JSON-Antwort zu lesen.
    private func parseAPIError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
