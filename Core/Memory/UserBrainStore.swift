//
//  UserBrainStore.swift
//  Voicefinder
//
//  Persistenz für das KI-Gehirn (JSON im App-Support-Verzeichnis).
//

import Foundation

/// Speichert und lädt das Nutzerprofil dauerhaft auf dem Gerät.
actor UserBrainStore {
    /// Gemeinsame Instanz für Orchestrator und UI.
    static let shared = UserBrainStore()

    private let fileURL: URL
    private var profile: UserBrainProfile

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Voicefinder", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("user-brain-profile.json", isDirectory: false)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = UserBrainProfile.decodePayload(data) {
            profile = decoded
        } else {
            profile = UserBrainProfile()
        }
    }

    /// Aktuelles Profil (ohne Speichern).
    func currentProfile() -> UserBrainProfile {
        profile
    }

    /// Ersetzt das gesamte Profil und speichert es.
    @discardableResult
    func save(_ newProfile: UserBrainProfile) -> UserBrainProfile {
        var updated = newProfile
        _ = updated.syncStandardFieldsFromEntries()
        updated.lastUpdated = Date()
        profile = updated
        persist()
        return profile
    }

    /// Löscht nur Nutzer-Infos – KI-Name und Auftrag bleiben erhalten.
    @discardableResult
    func clearUserProfileOnly() -> UserBrainProfile {
        var working = profile
        working.clearUserProfileOnly()
        profile = working
        persist()
        NSLog("[Voicefinder] KI-Gehirn: Nutzerprofil gelöscht (Name/Auftrag bleiben).")
        return profile
    }

    /// Profil aus Nutzeräußerung ergänzen (Regeln).
    @discardableResult
    func ingestUserMessage(_ text: String) -> UserBrainProfile {
        var working = profile
        let rulesChanged = UserBrainExtractor.apply(to: &working, from: text)
        let synced = working.syncStandardFieldsFromEntries()
        if rulesChanged || synced {
            profile = working
            persist()
            NSLog("[Voicefinder] KI-Gehirn: Profil aus Gespräch aktualisiert.")
        }
        return profile
    }

    /// Ergänzt Profil per Regeln + lokalem LLM im Hintergrund.
    @discardableResult
    func enrichFromMessage(_ text: String) async -> UserBrainProfile {
        var working = profile
        let rulesChanged = UserBrainExtractor.apply(to: &working, from: text)

        let llmFacts = await UserBrainLLMExtractor.extractFacts(from: text, existingProfile: working)
        let llmChanged = UserBrainExtractor.applyCandidates(llmFacts, to: &working, discoveredByAI: true)
        let synced = working.syncStandardFieldsFromEntries()

        if llmChanged || rulesChanged || synced {
            profile = working
            persist()
            NSLog("[Voicefinder] KI-Gehirn: %d neue Einträge (LLM/Regeln).", llmFacts.count)
        }

        return profile
    }

    // MARK: - Intern

    private func persist() {
        guard let data = profile.encodedPayload() else {
            NSLog("[Voicefinder] KI-Gehirn Speichern fehlgeschlagen: Kodierung.")
            return
        }
        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("[Voicefinder] KI-Gehirn Speichern fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
