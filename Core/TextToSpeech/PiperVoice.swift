//
//  PiperVoice.swift
//  Voicefinder
//
//  Deutsche Piper-Stimmen (Sherpa-ONNX / VITS-Piper).
//

import Foundation

/// Bekannte deutsche Piper-Stimmen im App-Bundle unter `Resources/Models/piper-de/voices/`.
enum PiperVoice: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Thorsten – männlich, mittlere Qualität (Standard).
    case thorstenMedium = "thorsten-medium"
    /// Thorsten – männlich, kompakt/schneller.
    case thorstenLow = "thorsten-low"
    /// Kerstin – weiblich, kompakt.
    case kerstinLow = "kerstin-low"
    /// Eva – weiblich, sehr kompakt.
    case evaLow = "eva_k-x_low"

    nonisolated var id: String { rawValue }

    /// Anzeigename in der Stimmen-Auswahl.
    nonisolated var displayName: String {
        switch self {
        case .thorstenMedium:
            "Thorsten (mittel)"
        case .thorstenLow:
            "Thorsten (kompakt)"
        case .kerstinLow:
            "Kerstin"
        case .evaLow:
            "Eva"
        }
    }

    /// Kurzbeschreibung für die Einstellungs-UI.
    nonisolated var subtitle: String {
        switch self {
        case .thorstenMedium:
            "Natürliche männliche Stimme – empfohlen"
        case .thorstenLow:
            "Männlich, schnellere Synthese"
        case .kerstinLow:
            "Weibliche Stimme"
        case .evaLow:
            "Weibliche Stimme, sehr kompakt"
        }
    }

    /// Dateiname der ONNX-Datei im eingebetteten Stimmen-Unterordner.
    nonisolated var onnxFileName: String {
        switch self {
        case .thorstenMedium:
            "de_DE-thorsten-medium.onnx"
        case .thorstenLow:
            "de_DE-thorsten-low.onnx"
        case .kerstinLow:
            "de_DE-kerstin-low.onnx"
        case .evaLow:
            "de_DE-eva_k-x_low.onnx"
        }
    }

    /// Ordnername unter `piper-de/voices/`.
    nonisolated var bundleSubdirectory: String { rawValue }
}
