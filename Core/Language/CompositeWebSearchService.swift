//
//  CompositeWebSearchService.swift
//  Voicefinder
//
//  Recherche-Reihenfolge: 1. Wikipedia, 2. gewählte Suchmaschine (Google oder DuckDuckGo).
//

import Foundation

/// Kombiniert Wikipedia (immer zuerst) mit der in den Einstellungen gewählten Suchmaschine.
struct CompositeWebSearchService: WebSearchProviding, Sendable {
    private let wikipedia: WikipediaSearchService
    private let duckDuckGo: DuckDuckGoWebSearchService
    private let google: GoogleCustomSearchService

    init(
        wikipedia: WikipediaSearchService = WikipediaSearchService(),
        duckDuckGo: DuckDuckGoWebSearchService = DuckDuckGoWebSearchService(),
        google: GoogleCustomSearchService = GoogleCustomSearchService()
    ) {
        self.wikipedia = wikipedia
        self.duckDuckGo = duckDuckGo
        self.google = google
    }

    func fetchContext(for query: String) async throws -> String {
        var parts: [String] = []

        do {
            if let wiki = try await wikipedia.fetchSummary(for: query), !wiki.isEmpty {
                parts.append("Wikipedia: \(wiki)")
                NSLog("[Voicefinder] Web-Recherche: Wikipedia-Treffer.")
            } else {
                #if DEBUG
                NSLog("[Voicefinder] Web-Recherche: Wikipedia ohne Artikel für „%@“.", query)
                #endif
            }
        } catch {
            #if DEBUG
            NSLog("[Voicefinder] Web-Recherche: Wikipedia-Fehler: %@", String(describing: error))
            #endif
        }

        if let engineContext = await fetchFromConfiguredEngine(query: query), !engineContext.isEmpty {
            parts.append(engineContext)
        }

        let combined = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard WebSearchHeuristic.isUsefulWebContext(combined) else {
            throw WebSearchError.emptyResults
        }
        return combined
    }

    /// Ruft Google oder DuckDuckGo gemäß Nutzer-Einstellung auf.
    private func fetchFromConfiguredEngine(query: String) async -> String? {
        switch AppSettingsStore.webSearchEngine {
        case .google:
            if google.isConfigured {
                if let context = try? await google.fetchContext(for: query) {
                    NSLog("[Voicefinder] Web-Recherche: Google.")
                    return context
                }
                NSLog("[Voicefinder] Google fehlgeschlagen – Fallback DuckDuckGo.")
            } else {
                NSLog("[Voicefinder] Google nicht konfiguriert – nutze DuckDuckGo.")
            }
            fallthrough
        case .duckDuckGo:
            do {
                let context = try await duckDuckGo.fetchContext(for: query)
                NSLog("[Voicefinder] Web-Recherche: DuckDuckGo.")
                return context
            } catch {
                #if DEBUG
                NSLog("[Voicefinder] Web-Recherche: DuckDuckGo-Fehler: %@", String(describing: error))
                #endif
                return nil
            }
        }
    }
}
