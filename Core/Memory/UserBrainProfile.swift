//
//  UserBrainProfile.swift
//  Voicefinder
//
//  Dauerhaftes Nutzerprofil für das „KI-Gehirn“.
//

import Foundation

/// Prompt-relevante Ausschnitte aus dem KI-Gehirn für das lokale LLM.
struct UserBrainPromptContext: Sendable, Equatable {
    var assistantName: String?
    var assistantNameDirective: String?
    var profilePromptBlock: String?
    var resolvedCity: String?
    var discoveryDirective: String?
    var userFirstName: String?
    var userFirstNameDirective: String?
    var mission: String?
    var missionDirective: String?
    var missionConversationDirective: String?

    nonisolated init(
        assistantName: String? = nil,
        assistantNameDirective: String? = nil,
        profilePromptBlock: String? = nil,
        resolvedCity: String? = nil,
        discoveryDirective: String? = nil,
        userFirstName: String? = nil,
        userFirstNameDirective: String? = nil,
        mission: String? = nil,
        missionDirective: String? = nil,
        missionConversationDirective: String? = nil
    ) {
        self.assistantName = assistantName
        self.assistantNameDirective = assistantNameDirective
        self.profilePromptBlock = profilePromptBlock
        self.resolvedCity = resolvedCity
        self.discoveryDirective = discoveryDirective
        self.userFirstName = userFirstName
        self.userFirstNameDirective = userFirstNameDirective
        self.mission = mission
        self.missionDirective = missionDirective
        self.missionConversationDirective = missionConversationDirective
    }

    /// Vorname für gesprochene Anrede im LLM-Prompt.
    nonisolated var resolvedUserFirstName: String? {
        let trimmed = userFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Auftragstext, falls gesetzt.
    nonisolated var resolvedMission: String {
        mission?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Bekannte Profilfelder, die die KI sammeln und nutzen soll.
enum UserBrainField: String, CaseIterable, Identifiable, Sendable, Codable {
    case firstName
    case lastName
    case gender
    case profession
    case street
    case city
    case age
    case hobbies
    case maritalStatus
    case car
    case height
    case pets
    case favoriteColor

    nonisolated var id: String { rawValue }

    /// Anzeigename in der UI.
    nonisolated var displayName: String {
        switch self {
        case .firstName: "Vorname"
        case .lastName: "Nachname"
        case .gender: "Geschlecht"
        case .profession: "Beruf"
        case .street: "Straße"
        case .city: "Wohnort"
        case .age: "Alter"
        case .hobbies: "Hobbies"
        case .maritalStatus: "Familienstand"
        case .car: "Auto"
        case .height: "Größe"
        case .pets: "Haustiere"
        case .favoriteColor: "Lieblingsfarbe"
        }
    }

    /// Platzhalter für Textfelder.
    nonisolated var placeholder: String {
        switch self {
        case .firstName: "z. B. Markus"
        case .lastName: "z. B. Ringe"
        case .gender: "z. B. männlich"
        case .profession: "z. B. Lehrer"
        case .street: "z. B. Musterstraße 12"
        case .city: "z. B. Berlin"
        case .age: "z. B. 32"
        case .hobbies: "z. B. Wandern, Kochen"
        case .maritalStatus: "z. B. verheiratet"
        case .car: "z. B. VW Golf"
        case .height: "z. B. 1,78 m"
        case .pets: "z. B. Hund Bello, Katze Mimi"
        case .favoriteColor: "z. B. Blau"
        }
    }

    /// Beispiel-Frage, die die KI stellen kann, wenn das Feld fehlt.
    nonisolated var discoveryQuestion: String {
        switch self {
        case .firstName: "Wie darf ich dich nennen?"
        case .lastName: "Wie ist dein Nachname?"
        case .gender: "Darf ich fragen, welches Geschlecht du hast?"
        case .profession: "Was machst du beruflich?"
        case .street: "In welcher Straße wohnst du?"
        case .city: "Wo wohnst du?"
        case .age: "Wie alt bist du, wenn ich fragen darf?"
        case .hobbies: "Was machst du gern in deiner Freizeit?"
        case .maritalStatus: "Bist du single, verheiratet oder in einer Beziehung?"
        case .car: "Fährst du ein Auto – und welches?"
        case .height: "Wie groß bist du ungefähr?"
        case .pets: "Hast du Haustiere?"
        case .favoriteColor: "Was ist deine Lieblingsfarbe?"
        }
    }

    /// Ordnet ein freies Label einem Standardfeld zu (für KI-Einträge).
    nonisolated static func matchingField(forLabel label: String) -> UserBrainField? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: UserBrainField] = [
            "vorname": .firstName,
            "rufname": .firstName,
            "nachname": .lastName,
            "familienname": .lastName,
            "geschlecht": .gender,
            "beruf": .profession,
            "tätigkeit": .profession,
            "taetigkeit": .profession,
            "job": .profession,
            "straße": .street,
            "strasse": .street,
            "adresse": .street,
            "wohnort": .city,
            "stadt": .city,
            "ort": .city,
            "alter": .age,
            "hobbies": .hobbies,
            "hobby": .hobbies,
            "familienstand": .maritalStatus,
            "beziehungsstatus": .maritalStatus,
            "auto": .car,
            "fahrzeug": .car,
            "wagen": .car,
            "größe": .height,
            "groesse": .height,
            "körpergröße": .height,
            "koerpergroesse": .height,
            "haustiere": .pets,
            "haustier": .pets,
            "tiername": .pets,
            "lieblingsfarbe": .favoriteColor,
            "farbe": .favoriteColor,
            // Legacy: „Name“ nur als Vorname, wenn kein Nachname gemeint ist
            "name": .firstName,
            "mein name": .firstName,
            "nutzername": .firstName,
        ]
        return map[normalized]
    }
}

/// Ein einzelner, bearbeitbarer Profil-Eintrag (Standard oder von der KI entdeckt).
struct UserBrainEntry: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var label: String
    var value: String
    /// True, wenn die KI diesen Punkt eigenständig angelegt hat.
    var discoveredByAI: Bool
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        label: String,
        value: String,
        discoveredByAI: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.discoveredByAI = discoveredByAI
        self.updatedAt = updatedAt
    }
}

/// Gespeichertes Nutzerprofil + KI-Name – rein lokal auf dem Gerät.
struct UserBrainProfile: Codable, Sendable, Equatable {
    /// Vom Nutzer vergebener Name der KI (z. B. „Luna“).
    var assistantName: String = ""
    /// Grund, warum die KI das Gespräch führen soll – löst die Gesprächseröffnung aus.
    var mission: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var gender: String = ""
    var profession: String = ""
    var street: String = ""
    var city: String = ""
    var age: String = ""
    var hobbies: String = ""
    var maritalStatus: String = ""
    var car: String = ""
    var height: String = ""
    var pets: String = ""
    var favoriteColor: String = ""
    /// Dynamische Einträge – von der KI entdeckt oder vom Nutzer angelegt.
    var entries: [UserBrainEntry] = []
    var lastUpdated: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case assistantName, mission
        case firstName, lastName, gender, profession, street, city
        case age, hobbies, maritalStatus, car, height, pets, favoriteColor
        case entries, lastUpdated
        case additionalNotes
        case petName // Legacy – wird in pets migriert
    }

    /// Normalisierter Auftragstext oder leer.
    nonisolated var resolvedMission: String {
        mission.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True, wenn ein Auftrag hinterlegt ist.
    nonisolated var hasMission: Bool {
        !resolvedMission.isEmpty
    }

    /// True, wenn mindestens ein Nutzerprofil-Feld befüllt ist (ohne KI-Name und Auftrag).
    nonisolated var hasUserProfileData: Bool {
        UserBrainField.allCases.contains { !value(for: $0).isEmpty }
            || entries.contains { !$0.label.isEmpty && !$0.value.isEmpty }
    }

    /// True, wenn mindestens ein Feld befüllt ist.
    nonisolated var hasAnyData: Bool {
        !assistantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasMission
            || hasUserProfileData
    }

    /// Löscht nur Nutzerdaten – KI-Name und Auftrag bleiben erhalten.
    nonisolated mutating func clearUserProfileOnly() {
        firstName = ""
        lastName = ""
        gender = ""
        profession = ""
        street = ""
        city = ""
        age = ""
        hobbies = ""
        maritalStatus = ""
        car = ""
        height = ""
        pets = ""
        favoriteColor = ""
        entries = []
        lastUpdated = Date()
    }

    /// Hinweise für eine Gesprächseröffnung ohne Auftrag (KI-Gehirn + Ort).
    nonisolated func conversationOpeningHints() -> [String] {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        var hints: [String] = []

        let firstName = working.resolvedValue(for: .firstName)
        if !firstName.isEmpty {
            hints.append("Vorname des Gesprächspartners: \(firstName)")
        }

        let city = working.resolvedValue(for: .city)
        if !city.isEmpty {
            hints.append("Wohnort: \(city) – du darfst Wetter oder lokales Alltagswissen anspielen.")
        }

        for field in UserBrainField.allCases where field != .firstName && field != .city {
            let value = working.resolvedValue(for: field)
            if !value.isEmpty {
                hints.append("\(field.displayName): \(value)")
            }
        }

        for entry in working.entries where !entry.label.isEmpty && !entry.value.isEmpty {
            if UserBrainField.matchingField(forLabel: entry.label) != nil { continue }
            hints.append("\(entry.label): \(entry.value)")
        }

        return hints
    }

    /// Anzahl ausgefüllter Standardfelder (für UI-Fortschritt).
    nonisolated var filledStandardFieldCount: Int {
        UserBrainField.allCases.filter { isFieldFilled($0) }.count
    }

    /// Anzahl sinnvoller dynamischer Einträge.
    nonisolated var filledEntryCount: Int {
        entries.filter { !$0.label.isEmpty && !$0.value.isEmpty }.count
    }

    nonisolated func value(for field: UserBrainField) -> String {
        switch field {
        case .firstName: firstName
        case .lastName: lastName
        case .gender: gender
        case .profession: profession
        case .street: street
        case .city: city
        case .age: age
        case .hobbies: hobbies
        case .maritalStatus: maritalStatus
        case .car: car
        case .height: height
        case .pets: pets
        case .favoriteColor: favoriteColor
        }
    }

    nonisolated mutating func setValue(_ raw: String, for field: UserBrainField) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .firstName: firstName = trimmed
        case .lastName: lastName = trimmed
        case .gender: gender = trimmed
        case .profession: profession = trimmed
        case .street: street = trimmed
        case .city: city = trimmed
        case .age: age = trimmed
        case .hobbies: hobbies = trimmed
        case .maritalStatus: maritalStatus = trimmed
        case .car: car = trimmed
        case .height: height = trimmed
        case .pets: pets = trimmed
        case .favoriteColor: favoriteColor = trimmed
        }
    }

    /// True, wenn das Feld (Standard oder passender dynamischer Eintrag) befüllt ist.
    nonisolated func isFieldFilled(_ field: UserBrainField) -> Bool {
        !resolvedValue(for: field).isEmpty
    }

    /// Effektiver Wert: Standardfeld oder passender dynamischer Eintrag.
    nonisolated func resolvedValue(for field: UserBrainField) -> String {
        let direct = value(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        for entry in entries where !entry.value.isEmpty {
            if UserBrainField.matchingField(forLabel: entry.label) == field {
                return entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    /// Übernimmt dynamische Einträge in leere Standardfelder (z. B. „Name“ → Vorname).
    /// - Returns: True, wenn mindestens ein Standardfeld befüllt wurde.
    @discardableResult
    nonisolated mutating func syncStandardFieldsFromEntries() -> Bool {
        var changed = false
        for entry in entries where !entry.label.isEmpty && !entry.value.isEmpty {
            guard let field = UserBrainField.matchingField(forLabel: entry.label) else { continue }
            if value(for: field).isEmpty {
                setValue(entry.value, for: field)
                changed = true
            }
        }
        return changed
    }

    /// Felder, die noch leer sind – Ziel für dezentes Kennenlernen.
    nonisolated func missingFields() -> [UserBrainField] {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        return UserBrainField.allCases.filter { !working.isFieldFilled($0) }
    }

    /// Fügt einen Eintrag hinzu oder aktualisiert einen passenden (nach Label).
    /// Standardfelder werden bevorzugt befüllt, wenn das Label passt und das Feld leer ist.
    nonisolated mutating func upsertDiscoveredFact(
        label: String,
        factValue: String,
        discoveredByAI: Bool,
        allowOverwriteStandard: Bool = false
    ) -> Bool {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = factValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return false }

        if let field = UserBrainField.matchingField(forLabel: trimmedLabel) {
            if value(for: field).isEmpty || allowOverwriteStandard {
                setValue(trimmedValue, for: field)
                lastUpdated = Date()
                return true
            }
        }

        let normalizedNew = trimmedLabel.lowercased()
        if let index = entries.firstIndex(where: { $0.label.lowercased() == normalizedNew }) {
            if entries[index].value.isEmpty || discoveredByAI == false {
                entries[index].value = trimmedValue
                entries[index].discoveredByAI = entries[index].discoveredByAI && discoveredByAI
                entries[index].updatedAt = Date()
                lastUpdated = Date()
                return true
            }
            return false
        }

        entries.append(
            UserBrainEntry(
                label: trimmedLabel,
                value: trimmedValue,
                discoveredByAI: discoveredByAI
            )
        )
        lastUpdated = Date()
        return true
    }

    /// Entfernt einen dynamischen Eintrag.
    nonisolated mutating func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        lastUpdated = Date()
    }

    /// Aktualisiert Label und Wert eines dynamischen Eintrags (Nutzer-Bearbeitung).
    nonisolated mutating func updateEntry(id: UUID, label: String, value: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].discoveredByAI = false
        entries[index].updatedAt = Date()
        lastUpdated = Date()
    }

    /// Legt einen leeren Eintrag für manuelle Bearbeitung an.
    nonisolated mutating func addEmptyEntry() {
        entries.append(UserBrainEntry(label: "", value: "", discoveredByAI: false))
        lastUpdated = Date()
    }

    /// Prompt-Block mit bekannten Nutzerinfos für das LLM.
    nonisolated func profilePromptBlock() -> String? {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        guard working.hasAnyData else { return nil }

        var lines: [String] = []
        for field in UserBrainField.allCases {
            let value = working.resolvedValue(for: field)
            if !value.isEmpty {
                lines.append("\(field.displayName): \(value)")
            }
        }

        for entry in working.entries where !entry.label.isEmpty && !entry.value.isEmpty {
            if UserBrainField.matchingField(forLabel: entry.label) != nil { continue }
            lines.append("\(entry.label): \(entry.value)")
        }

        guard !lines.isEmpty else { return nil }

        return """
        [Nutzerprofil – verbindlich, bereits gespeichert]
        \(lines.joined(separator: "\n"))
        Diese Fakten sind wahr. Nutze sie natürlich (z. B. Vorname ansprechen). \
        Frage NIEMALS erneut nach Infos, die hier stehen – besonders nicht nach dem Vornamen.
        """
    }

    /// Kurzliste bekannter Fakten – explizites Verbot zum Wiederholen von Fragen.
    nonisolated func knownFactsSummary() -> String? {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        var lines: [String] = []
        for field in UserBrainField.allCases {
            let value = working.resolvedValue(for: field)
            if !value.isEmpty {
                lines.append("\(field.displayName): \(value)")
            }
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// Verbindliche Anweisung zum Nutzer-Vornamen – verhindert Endlosschleifen beim Nachfragen.
    nonisolated func userFirstNameDirective() -> String? {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        let name = working.resolvedValue(for: .firstName)
        guard !name.isEmpty else { return nil }
        return """
        [Nutzer-Vorname – verbindlich]
        Der Nutzer heißt „\(name)“. Sprich ihn natürlich mit „\(name)“ an, wenn es passt.
        Frage NIEMALS nach seinem Namen, Vornamen oder „wie ich dich nennen soll“.
        """
    }

    /// Anweisung: fehlende Infos nebenbei sammeln – ohne Formular-Ton und ohne Endlosschleifen.
    nonisolated func discoveryDirective() -> String {
        var working = self
        _ = working.syncStandardFieldsFromEntries()

        // Bei aktivem Rollen-Auftrag kein Profil-Sammeln – verhindert Ablenkung und Schleifen.
        if !working.resolvedMission.isEmpty {
            return """
            [Profil im Gespräch]
            Rollen-Gespräch aktiv – kein Profil-Sammeln, keine Formular-Fragen.
            Antworte nur auf die aktuelle Äußerung des Gesprächspartners.
            """
        }

        let missing = working.missingFields()
        let userNameKnown = !working.resolvedValue(for: .firstName).isEmpty

        var text = """
        [Profil im Gespräch]
        Merke dir Neues aus dem Gespräch (Alltag, Vorlieben, Beruf) – landet im KI-Gehirn.
        """

        if let known = working.knownFactsSummary() {
            text += """

            Bereits bekannt – nicht erneut erfragen:
            \(known)
            """
        }

        if missing.isEmpty {
            text += """

            Das Profil reicht für den Alltag. Kein aktives Nachfragen nötig.
            """
        } else {
            // Vorname nie als „offenes Feld“ listen, wenn er schon bekannt ist.
            let missingForPrompt = missing.filter { field in
                !(field == .firstName && userNameKnown)
            }
            let priority = missingForPrompt.prefix(2).map(\.displayName).joined(separator: ", ")
            if priority.isEmpty {
                text += """

                Profil ist ausreichend. Keine Profil-Fragen stellen.
                """
            } else {
                text += """

                Optional noch offen (nur \(priority)) – höchstens selten und unaufdringlich ergänzen:
                - Nicht in jeder Antwort nachfragen; oft lieber gar keine Profil-Frage
                - Nie Formular-Ton („Wie heißt du?“, „Wie darf ich dich nennen?“)
                - Erst die Nutzerfrage beantworten; Profil-Frage nur wenn sie natürlich passt
                - Wenn ein Name im Profil steht: diesen nutzen, nie erneut nach dem Namen fragen
                """
            }
        }

        return text
    }

    /// KI-Namen für den System-Prompt (falls gesetzt).
    nonisolated func assistantNameDirective() -> String? {
        let name = assistantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return """
        [Dein Name – verbindlich]
        Du heißt „\(name)“. Bei Fragen nach deinem Namen antworte natürlich mit „\(name)“ oder „Ich heiße \(name)“.
        """
    }

    /// Regeln für laufendes Rollen-Gespräch – verhindert Wiederholungen und App-Bezug.
    nonisolated func missionConversationDirective() -> String? {
        guard !resolvedMission.isEmpty else { return nil }
        return """
        [Rollen-Gespräch – verbindlich]
        Du bist mitten im Gespräch in deiner Rolle – kein Neustart, keine Wiederholung deiner Einleitung.
        Wenn du Termin, Rolle oder Anliegen schon genannt hast: nicht nochmal sagen.
        Der Gesprächspartner ist ein Mensch – nie App, Software, KI, Computer oder Voicefinder erwähnen.
        Wiederhole nie denselben Satz oder dasselbe Skript wie in deiner letzten Antwort.
        Keine leeren Bestätigungen wie „Alles klar“, „Verstanden“ oder „Okay“ allein – \
        immer auf den Nutzer eingehen und mit einer echten Folgefrage weitermachen.
        Bei Fragen: kurz und menschlich antworten, dann wenn passend nachfragen – nicht das Rollen-Skript von vorne spielen.
        Erfinde keine Uhrzeiten, Termine oder konkreten Zahlen, die der Nutzer nicht genannt hat.
        """
    }

    /// Auftrag für das LLM – beschreibt die Rolle der KI, nicht den Gesprächspartner.
    nonisolated func missionDirective() -> String? {
        let text = resolvedMission
        guard !text.isEmpty else { return nil }
        return """
        [Deine Rolle – verbindlich, nur intern]
        Du nimmst in diesem Gespräch folgende Rolle ein: \(text)
        Das ist DEINE Rolle – nicht die Identität oder die Daten des Gesprächspartners.
        Stelle die Rolle nur einmal zu Beginn vor – danach nicht wiederholen.
        Vermische die Rolle nicht mit Nutzer-Profilinfos. Sprich die Rolle nie wörtlich als Regie aus \
        (kein „Mein Auftrag ist…“, kein „Intermezzo“, keine Regieanweisungen).
        """
    }

    /// Prompt-Kontext nur für Rollen/Auftrag – ohne Nutzer-Profil (Gesprächseröffnung).
    nonisolated func missionRolePromptContext() -> UserBrainPromptContext {
        return UserBrainPromptContext(
            assistantName: assistantName.isEmpty ? nil : assistantName,
            assistantNameDirective: assistantNameDirective(),
            profilePromptBlock: nil,
            resolvedCity: nil,
            discoveryDirective: """
            [Rollen-Gespräch]
            Sprich nur natürliche Dialogsätze wie ein echter Mensch. Keine Meta-Kommentare, kein App-Bezug.
            Stelle deine Rolle nur einmal vor – nicht wiederholen.
            """,
            userFirstName: nil,
            userFirstNameDirective: nil,
            mission: resolvedMission.isEmpty ? nil : resolvedMission,
            missionDirective: missionDirective(),
            missionConversationDirective: missionConversationDirective()
        )
    }

    /// Erzeugt den Prompt-Kontext für die Sprach-Pipeline.
    nonisolated func promptContext() -> UserBrainPromptContext {
        var working = self
        _ = working.syncStandardFieldsFromEntries()
        let city = working.resolvedValue(for: .city)
        let firstName = working.resolvedValue(for: .firstName)
        let missionText = working.resolvedMission
        return UserBrainPromptContext(
            assistantName: working.assistantName.isEmpty ? nil : working.assistantName,
            assistantNameDirective: working.assistantNameDirective(),
            profilePromptBlock: working.profilePromptBlock(),
            resolvedCity: city.isEmpty ? nil : city,
            discoveryDirective: working.discoveryDirective(),
            userFirstName: firstName.isEmpty ? nil : firstName,
            userFirstNameDirective: working.userFirstNameDirective(),
            mission: missionText.isEmpty ? nil : missionText,
            missionDirective: working.missionDirective(),
            missionConversationDirective: working.missionConversationDirective()
        )
    }

    /// JSON-Kodierung für persistente Speicherung (explizit nonisolated für Swift 6).
    nonisolated func encodedPayload() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    /// JSON-Dekodierung aus gespeicherten Daten.
    nonisolated static func decodePayload(_ data: Data) -> UserBrainProfile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UserBrainProfile.self, from: data)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantName = try container.decodeIfPresent(String.self, forKey: .assistantName) ?? ""
        mission = try container.decodeIfPresent(String.self, forKey: .mission) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? ""
        profession = try container.decodeIfPresent(String.self, forKey: .profession) ?? ""
        street = try container.decodeIfPresent(String.self, forKey: .street) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
        hobbies = try container.decodeIfPresent(String.self, forKey: .hobbies) ?? ""
        maritalStatus = try container.decodeIfPresent(String.self, forKey: .maritalStatus) ?? ""
        car = try container.decodeIfPresent(String.self, forKey: .car) ?? ""
        height = try container.decodeIfPresent(String.self, forKey: .height) ?? ""
        pets = try container.decodeIfPresent(String.self, forKey: .pets) ?? ""
        favoriteColor = try container.decodeIfPresent(String.self, forKey: .favoriteColor) ?? ""
        entries = try container.decodeIfPresent([UserBrainEntry].self, forKey: .entries) ?? []
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()

        // Legacy: früheres Feld „Tiername“ → Haustiere
        let legacyPetName = try container.decodeIfPresent(String.self, forKey: .petName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if pets.isEmpty, !legacyPetName.isEmpty {
            pets = legacyPetName
        }

        let legacyNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacyNotes.isEmpty, entries.isEmpty {
            entries = [UserBrainEntry(label: "Notizen", value: legacyNotes, discoveredByAI: false)]
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assistantName, forKey: .assistantName)
        try container.encode(mission, forKey: .mission)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(gender, forKey: .gender)
        try container.encode(profession, forKey: .profession)
        try container.encode(street, forKey: .street)
        try container.encode(city, forKey: .city)
        try container.encode(age, forKey: .age)
        try container.encode(hobbies, forKey: .hobbies)
        try container.encode(maritalStatus, forKey: .maritalStatus)
        try container.encode(car, forKey: .car)
        try container.encode(height, forKey: .height)
        try container.encode(pets, forKey: .pets)
        try container.encode(favoriteColor, forKey: .favoriteColor)
        try container.encode(entries, forKey: .entries)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    nonisolated init() {}
}
