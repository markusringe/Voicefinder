//
//  AppSettingsStore.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Gewählte Suchmaschine nach der Wikipedia-Stufe.
enum WebSearchEngine: String, CaseIterable, Identifiable, Sendable, Codable {
    case duckDuckGo
    case google

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .duckDuckGo: "Kein API-Schlüssel nötig."
        case .google: "Benötigt API-Schlüssel und Suchmaschinen-ID (cx)."
        }
    }
}

/// Persistierte App-Einstellungen (UserDefaults).
enum AppSettingsStore {
    /// Internet-Recherche für faktische / aktuelle Fragen.
    nonisolated static let internetEnabledKey = "voicefinder.internetEnabled"

    /// Gewählte Piper-Stimme (`PiperVoice.rawValue`).
    nonisolated static let piperVoiceKey = "voicefinder.piperVoice"

    /// Sprechgeschwindigkeit für Piper (0.5 … 2.0, Standard 1.0).
    nonisolated static let piperSpeedKey = "voicefinder.piperSpeed"

    /// Gewählter KI-Antwort-Stil (`AIInteractionStyle.rawValue`).
    nonisolated static let aiInteractionStyleKey = "voicefinder.aiInteractionStyle"

    /// Google Custom Search API-Schlüssel.
    nonisolated static let googleSearchAPIKeyKey = "voicefinder.googleSearchAPIKey"

    /// Google Programmable Search Engine ID (cx).
    nonisolated static let googleSearchEngineIDKey = "voicefinder.googleSearchEngineID"

    /// Info.plist-Schlüssel für optionalen Google-API-Key beim Build.
    nonisolated static let googleSearchAPIKeyPlistKey = "GoogleCustomSearchAPIKey"

    /// Info.plist-Schlüssel für optionale Google-Suchmaschinen-ID beim Build.
    nonisolated static let googleSearchEngineIDPlistKey = "GoogleCustomSearchEngineID"

    /// True nach der einmaligen Standort-Einrichtung beim Start.
    nonisolated static let locationSetupCompletedKey = "voicefinder.locationSetupCompleted"

    /// Gewählte Suchmaschine (`WebSearchEngine.rawValue`).
    nonisolated static let webSearchEngineKey = "voicefinder.webSearchEngine"

    /// Frühes Sprechen: erster Satz wird vorgelesen, während das LLM noch generiert.
    nonisolated static let earlySpeechEnabledKey = "voicefinder.earlySpeechEnabled"

    /// True, wenn die KI vor Antworten im Web recherchieren darf (Standard: aus – nur bei Bedarf).
    nonisolated static var internetEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: internetEnabledKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: internetEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: internetEnabledKey)
        }
    }

    /// True, wenn der erste Satz schon während der LLM-Generierung gesprochen werden darf (Standard: an).
    /// Greift nur auf Geräten mit genug RAM – siehe `AppMemoryCoordinator.allowsConcurrentLLMAndTTS`.
    nonisolated static var earlySpeechEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: earlySpeechEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: earlySpeechEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: earlySpeechEnabledKey)
        }
    }

    /// Aktive Piper-Stimme (Fallback: Thorsten medium).
    nonisolated static var piperVoice: PiperVoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: piperVoiceKey),
                  let voice = PiperVoice(rawValue: raw) else {
                return .thorstenMedium
            }
            return voice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: piperVoiceKey)
        }
    }

    /// Piper-Sprechgeschwindigkeit – 1.0 entspricht der natürlichen Modellgeschwindigkeit.
    nonisolated static var piperSpeed: Float {
        get {
            let stored = UserDefaults.standard.object(forKey: piperSpeedKey) as? Float
            let value = stored ?? 1.08
            return min(max(value, 0.5), 2.0)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.5), 2.0), forKey: piperSpeedKey)
        }
    }

    /// Aktiver KI-Stil (Normal, Forsch, Frech, Lustig, Schlau).
    nonisolated static var aiInteractionStyle: AIInteractionStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: aiInteractionStyleKey),
                  let style = AIInteractionStyle(rawValue: raw) else {
                return .normal
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: aiInteractionStyleKey)
        }
    }

    /// Google API-Schlüssel – aus UserDefaults oder Info.plist.
    nonisolated static var googleSearchAPIKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: googleSearchAPIKeyKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stored.isEmpty { return stored }

            if let plist = Bundle.main.object(forInfoDictionaryKey: googleSearchAPIKeyPlistKey) as? String {
                let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: googleSearchAPIKeyKey)
        }
    }

    /// Google Suchmaschinen-ID (cx) – aus UserDefaults oder Info.plist.
    nonisolated static var googleSearchEngineID: String {
        get {
            let stored = UserDefaults.standard.string(forKey: googleSearchEngineIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stored.isEmpty { return stored }

            if let plist = Bundle.main.object(forInfoDictionaryKey: googleSearchEngineIDPlistKey) as? String {
                let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: googleSearchEngineIDKey)
        }
    }

    /// True, wenn Google als primäre Suchquelle nutzbar ist.
    nonisolated static var isGoogleSearchConfigured: Bool {
        !googleSearchAPIKey.isEmpty && !googleSearchEngineID.isEmpty
    }

    /// Suchmaschine nach Wikipedia (Standard: DuckDuckGo).
    nonisolated static var webSearchEngine: WebSearchEngine {
        get {
            guard let raw = UserDefaults.standard.string(forKey: webSearchEngineKey),
                  let engine = WebSearchEngine(rawValue: raw) else {
                return .duckDuckGo
            }
            return engine
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: webSearchEngineKey)
        }
    }

    /// True, wenn die einmalige Standort-Abfrage beim Start bereits erfolgt ist.
    nonisolated static var locationSetupCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: locationSetupCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: locationSetupCompletedKey) }
    }
}
