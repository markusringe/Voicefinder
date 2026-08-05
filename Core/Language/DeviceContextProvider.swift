//
//  DeviceContextProvider.swift
//  Voicefinder
//
//  Liefert Gerätekontext (Uhrzeit, Datum, Zeitzone) für das lokale LLM –
//  ohne Standortberechtigung.
//

import Foundation

/// Aktueller Gerätekontext für Sprachantworten (Uhrzeit, Datum, Region).
enum DeviceContextProvider: Sendable {
    /// Deutsch formatiertes Datum und Uhrzeit.
    nonisolated private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    /// Nur Uhrzeit (24h), für kompakte Prompt-Zeilen.
    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Nur Kalenderdatum.
    nonisolated private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// Baut den Kontextblock für den System-Prompt – wird bei jeder Anfrage frisch erzeugt.
    nonisolated static func contextBlock(for date: Date = Date(), city: String? = nil) -> String {
        let locale = Locale.current
        let timeZone = TimeZone.current
        let regionName = locale.localizedString(forRegionCode: locale.region?.identifier ?? "") ?? "Unbekannt"
        let timeZoneName = timeZone.localizedName(for: .standard, locale: locale) ?? timeZone.identifier
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locationLine: String
        if trimmedCity.isEmpty {
            locationLine = "Wohnort: noch unbekannt (steht im KI-Gehirn, sobald bekannt)."
        } else {
            locationLine = "Wohnort (KI-Gehirn): \(trimmedCity) – nutze diesen Ort für lokale Infos und Wetter."
        }

        return """
        [Gerätekontext – verbindlich für Uhrzeit, Datum und Ort]
        Jetzt: \(dateTimeFormatter.string(from: date))
        Uhrzeit: \(timeFormatter.string(from: date))
        Datum: \(dateFormatter.string(from: date))
        Zeitzone: \(timeZoneName) (\(timeZone.identifier))
        Region/Locale: \(regionName) (\(locale.identifier))
        \(locationLine)
        Hinweis: Uhrzeit und Datum stammen von der Geräteuhr. Für Wetter nutze den Wohnort aus dem KI-Gehirn.
        """
    }
}
