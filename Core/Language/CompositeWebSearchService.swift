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

    /// Zeichenbudget für die Wikipedia-Passage – genug für zwei Sätze, wenig Prefill für das 1,7B-Modell.
    private static let passageBudget = 450

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

        // Schlüsselwörter statt ganzer Satz – der Satz liefert oft den falschen Artikel.
        let searchQuery = WebSearchQuery.make(from: query)
        do {
            if let passage = try await wikipedia.fetchPassage(for: searchQuery, maxCharacters: Self.passageBudget) {
                parts.append("Wikipedia – \(passage)")
                NSLog("[Voicefinder] Web-Recherche: Wikipedia-Treffer.")
            } else {
                #if DEBUG
                NSLog("[Voicefinder] Web-Recherche: keine passende Wikipedia-Passage für „%@“.", searchQuery.searchTerms)
                #endif
            }
        } catch {
            #if DEBUG
            NSLog("[Voicefinder] Web-Recherche: Wikipedia-Fehler: %@", String(describing: error))
            #endif
        }

        // Nur ohne Wikipedia-Passage weitersuchen: Die DuckDuckGo-Instant-Answer-API liefert bei Fragesätzen
        // nichts und kostet nur Wartezeit; Google (falls konfiguriert) ergänzt, wenn Wikipedia nichts hat.
        if parts.isEmpty,
           let engineContext = await fetchFromConfiguredEngine(query: query), !engineContext.isEmpty {
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
