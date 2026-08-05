//
//  UserBrainExtractor.swift
//  Voicefinder
//
//  Erkennt Profil-Fakten aus Nutzeräußerungen (regelbasiert, offline).
//

import Foundation

/// Extrahiert strukturierte Profil-Informationen aus freiem Nutzertext.
enum UserBrainExtractor: Sendable {
    /// Wendet erkannte Fakten an – überschreibt nur leere Felder (manuelle Einträge bleiben).
    nonisolated static func apply(to profile: inout UserBrainProfile, from text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3 else { return false }

        var changed = false

        if !profile.isFieldFilled(.firstName), let name = extractFirstName(from: normalized) {
            profile.setValue(name, for: .firstName)
            changed = true
        }

        if !profile.isFieldFilled(.lastName), let lastName = extractLastName(from: normalized) {
            profile.setValue(lastName, for: .lastName)
            changed = true
        }

        if !profile.isFieldFilled(.gender), let genderValue = extractGender(from: normalized) {
            profile.setValue(genderValue, for: .gender)
            changed = true
        }

        if !profile.isFieldFilled(.profession), let profession = extractProfession(from: normalized) {
            profile.setValue(profession, for: .profession)
            changed = true
        }

        if !profile.isFieldFilled(.street), let street = extractStreet(from: normalized) {
            profile.setValue(street, for: .street)
            changed = true
        }

        if !profile.isFieldFilled(.city), let city = extractCity(from: normalized) {
            profile.setValue(city, for: .city)
            changed = true
        }

        if !profile.isFieldFilled(.age), let age = extractAge(from: normalized) {
            profile.setValue(age, for: .age)
            changed = true
        }

        if !profile.isFieldFilled(.hobbies), let hobbies = extractHobbies(from: normalized) {
            profile.setValue(hobbies, for: .hobbies)
            changed = true
        }

        if !profile.isFieldFilled(.maritalStatus), let status = extractMaritalStatus(from: normalized) {
            profile.setValue(status, for: .maritalStatus)
            changed = true
        }

        if !profile.isFieldFilled(.car), let car = extractCar(from: normalized) {
            profile.setValue(car, for: .car)
            changed = true
        }

        if !profile.isFieldFilled(.height), let height = extractHeight(from: normalized) {
            profile.setValue(height, for: .height)
            changed = true
        }

        if !profile.isFieldFilled(.pets), let pets = extractPets(from: normalized) {
            profile.setValue(pets, for: .pets)
            changed = true
        }

        if !profile.isFieldFilled(.favoriteColor), let color = extractFavoriteColor(from: normalized) {
            profile.setValue(color, for: .favoriteColor)
            changed = true
        }

        if profile.assistantName.isEmpty, let assistant = extractAssistantName(from: normalized) {
            profile.assistantName = assistant
            changed = true
        }

        changed = extractDynamicFacts(to: &profile, from: normalized) || changed

        if changed {
            profile.lastUpdated = Date()
        }

        return changed
    }

    /// Wendet eine Liste erkannter Fakten auf das Profil an.
    nonisolated static func applyCandidates(
        _ candidates: [UserBrainFactCandidate],
        to profile: inout UserBrainProfile,
        discoveredByAI: Bool
    ) -> Bool {
        var changed = false
        for candidate in candidates {
            if profile.upsertDiscoveredFact(
                label: candidate.label,
                factValue: candidate.value,
                discoveredByAI: discoveredByAI
            ) {
                changed = true
            }
        }
        return changed
    }

    /// Erkennt zusätzliche persönliche Fakten für dynamische Einträge.
    nonisolated private static func extractDynamicFacts(to profile: inout UserBrainProfile, from text: String) -> Bool {
        var changed = false
        let patterns: [(label: String, regex: String)] = [
            ("Lieblingsessen", #"(?i)(?:mein lieblingsessen ist|ich esse am liebsten|am liebsten esse ich)\s+(.{2,60})"#),
            ("Sport", #"(?i)(?:ich treibe sport|ich mache sport|ich gehe(?: gern)?)\s+(?:zum|zur|beim)?\s*([a-zäöüß][a-zäöüß\- ]{2,40})"#),
            ("Studium", #"(?i)(?:ich studiere|mein studium ist)\s+(.{2,50})"#),
            ("Kinder", #"(?i)(?:ich habe)\s+(\d+|ein|eine|zwei|drei|vier|fünf)\s+(?:kind|kinder|sohn|tochter|söhne|töchter)"#),
        ]

        for pattern in patterns {
            if let value = firstCapture(in: text, patterns: [pattern.regex])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) {
                if profile.upsertDiscoveredFact(label: pattern.label, factValue: value, discoveredByAI: true) {
                    changed = true
                }
            }
        }

        return changed
    }

    // MARK: - Einzelfelder

    nonisolated private static func extractFirstName(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich heiße|ich heisse|mein name ist|nenn(?:en)? mich)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,29})"#,
            #"(?i)^(?:hi,?\s*)?(?:ich bin)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,29})(?:\s*[,.!]|$)"#,
        ]
        return firstCapture(in: text, patterns: patterns).map(capitalizedFirstLetter)
    }

    nonisolated private static func extractLastName(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:mein nachname ist|nachname)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,39})"#,
            #"(?i)(?:ich heiße|ich heisse|mein name ist)\s+[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,29}\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,39})"#,
        ]
        return firstCapture(in: text, patterns: patterns).map(capitalizedFirstLetter)
    }

    nonisolated private static func extractGender(from text: String) -> String? {
        let lower = text.lowercased()
        let mapping: [(keywords: [String], value: String)] = [
            (["ich bin männlich", "bin ein mann", "bin mann"], "männlich"),
            (["ich bin weiblich", "bin eine frau", "bin frau"], "weiblich"),
            (["ich bin divers", "nicht-binär", "nicht binär", "non-binär"], "divers"),
        ]
        for entry in mapping where entry.keywords.contains(where: { lower.contains($0) }) {
            return entry.value
        }
        return nil
    }

    nonisolated private static func extractProfession(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich arbeite als|mein beruf ist|beruflich bin ich)\s+(?:ein(?:e|r|s)?\s+)?([a-zäöüß][a-zäöüß\- ]{2,40})"#,
            #"(?i)^(?:ich bin)\s+(?:ein(?:e|r|s)?\s+)?([a-zäöüß][a-zäöüß\- ]{2,40})(?:\s*[,.!]|$)"#,
        ]
        guard let raw = firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) else {
            return nil
        }
        // „Ich bin Markus“ o. Ä. nicht als Beruf werten
        let blocked = ["single", "verheiratet", "ledig", "männlich", "weiblich", "divers"]
        if blocked.contains(where: { raw.lowercased().contains($0) }) { return nil }
        if raw.split(separator: " ").count == 1, raw.first?.isUppercase == true, raw.count <= 12 {
            return nil
        }
        return capitalizedFirstLetter(raw)
    }

    nonisolated private static func extractStreet(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich wohne in der|meine adresse ist|ich wohne in)\s+([A-Za-zÄÖÜäöüß0-9][A-Za-zÄÖÜäöüß0-9\-\s]{2,60})"#,
            #"(?i)(?:straße|strasse)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-\s]{1,40}\s*\d{1,4}[a-z]?)"#,
        ]
        return firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }

    nonisolated private static func extractCity(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich wohne in|ich lebe in|komme aus|wohnhaft in|mein wohnort ist)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-\s]{1,40})"#,
        ]
        guard let raw = firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) else {
            return nil
        }
        return capitalizedFirstLetter(raw)
    }

    nonisolated private static func extractPets(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:mein (?:hund|katze|hamster|vogel|tier)|(?:hund|katze|tier) heißt|tier heißt|haustier heißt)\s+(?:heißt\s+)?([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-' ]{1,40})"#,
            #"(?i)(?:ich habe (?:einen hund|eine katze|ein tier|zwei hunde|zwei katzen)(?: namens| der heißt| die heißt)?)\s+(.{2,50})"#,
            #"(?i)(?:meine haustiere sind|ich habe haustiere:?)\s+(.{2,80})"#,
        ]
        return firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }

    nonisolated private static func extractCar(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich fahre|mein auto ist|ich habe ein auto)\s+(?:ein(?:en|e|em)?\s+)?(.{2,50})"#,
        ]
        return firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }

    nonisolated private static func extractFavoriteColor(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:meine lieblingsfarbe ist|lieblingsfarbe ist|lieblingsfarbe)\s+(.{2,30})"#,
        ]
        guard let raw = firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) else {
            return nil
        }
        return capitalizedFirstLetter(raw)
    }

    nonisolated private static func extractAge(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich bin|bin)\s+(\d{1,3})\s+(?:jahre alt|jahr(?:e)?(?: alt)?)"#,
            #"(?i)(?:ich bin|bin)\s+(\d{1,3})\s*$"#,
        ]
        guard let age = firstCapture(in: text, patterns: patterns),
              let years = Int(age), (1...120).contains(years) else {
            return nil
        }
        return "\(years)"
    }

    nonisolated private static func extractHobbies(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:mein hobby ist|meine hobbies sind|ich mag(?: gern)?|ich spiele gern|in meiner freizeit)\s+(.{3,80})"#,
        ]
        return firstCapture(in: text, patterns: patterns)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }

    nonisolated private static func extractMaritalStatus(from text: String) -> String? {
        let lower = text.lowercased()
        let mapping: [(keywords: [String], value: String)] = [
            (["verheiratet", "bin verheiratet"], "verheiratet"),
            (["ledig", "bin single", "ich bin single", "single und"], "ledig"),
            (["geschieden"], "geschieden"),
            (["in einer beziehung", "habe einen partner", "habe eine partnerin"], "in einer Beziehung"),
            (["verlobt"], "verlobt"),
        ]

        for entry in mapping where entry.keywords.contains(where: { lower.contains($0) }) {
            return entry.value
        }
        return nil
    }

    nonisolated private static func extractHeight(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:ich bin|größe|groß)\s+(?:ca\.?\s*)?(\d[,.]\d{1,2})\s*(?:m|meter)\b"#,
            #"(?i)(?:ich bin|größe)\s+(?:ca\.?\s*)?(\d{3})\s*cm\b"#,
        ]

        if let meters = firstCapture(in: text, patterns: [patterns[0]]) {
            return "\(meters.replacingOccurrences(of: ".", with: ",")) m"
        }

        if let cm = firstCapture(in: text, patterns: [patterns[1]]), let value = Int(cm) {
            let meters = Double(value) / 100.0
            return String(format: "%.2f m", meters).replacingOccurrences(of: ".", with: ",")
        }

        return nil
    }

    nonisolated private static func extractAssistantName(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:du heißt|dein name ist|nenn dich|nenne dich)\s+([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-']{1,29})"#,
        ]
        return firstCapture(in: text, patterns: patterns).map(capitalizedFirstLetter)
    }

    nonisolated private static func firstCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Erster Buchstabe groß (für Namen/Städte) – freistehend, damit Swift 6 kein MainActor erzwingt.
    nonisolated private static func capitalizedFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}
