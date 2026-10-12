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

    /// Jahreszeit (meteorologisch, Nordhalbkugel) – kleine Modelle leiten sie sonst falsch aus dem Datum ab.
    nonisolated static func season(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.month, from: date) {
        case 3 ... 5: "Frühling"
        case 6 ... 8: "Sommer"
        case 9 ... 11: "Herbst"
        default: "Winter"
        }
    }

    /// Kontextzeile für das Ende des System-Prompts – wird bei jeder Anfrage frisch erzeugt.
    /// Die Uhrzeit steht ganz am Ende: Ändert sich nur die Minute, bleibt der Prompt-Cache davor gültig.
    /// Der Wohnort steht in der Profilzeile des KI-Gehirns.
    nonisolated static func contextBlock(for date: Date = Date()) -> String {
        "Jetzt ist \(dateFormatter.string(from: date)) (\(season(for: date))), \(timeFormatter.string(from: date)) Uhr."
    }
}
