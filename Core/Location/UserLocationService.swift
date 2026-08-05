//
//  UserLocationService.swift
//  Voicefinder
//
//  Einmalige Standortermittlung per GPS + Reverse Geocoding (Stadt fürs KI-Gehirn).
//

import CoreLocation
import Foundation
import MapKit

/// Fehler bei der Standortermittlung.
enum UserLocationError: LocalizedError, Sendable {
    case denied
    case unavailable
    case geocodingFailed

    var errorDescription: String? {
        switch self {
        case .denied:
            "Standortzugriff wurde verweigert."
        case .unavailable:
            "Standort konnte nicht ermittelt werden."
        case .geocodingFailed:
            "Stadt konnte nicht aus dem Standort gelesen werden."
        }
    }
}

/// Ermittelt einmalig den Wohnort (Stadt) für das KI-Gehirn.
@MainActor
final class UserLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = UserLocationService()

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Fragt Berechtigung an und liefert den Stadtnamen (z. B. „Berlin“).
    func requestCityName() async throws -> String {
        let status = await ensureWhenInUseAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw UserLocationError.denied
        }

        let location = try await requestSingleLocation()
        return try await resolveCity(from: location)
    }

    // MARK: - Berechtigung

    private func ensureWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationContinuation?.resume(returning: manager.authorizationStatus)
            authorizationContinuation = nil
        }
    }

    // MARK: - GPS

    private func requestSingleLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    // MARK: - Geocoding (MapKit, iOS 26+)

    /// Löst GPS-Koordinaten per MapKit in einen Stadtnamen auf.
    private func resolveCity(from location: CLLocation) async throws -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw UserLocationError.geocodingFailed
        }

        let mapItems: [MKMapItem]
        do {
            mapItems = try await request.mapItems
        } catch {
            throw UserLocationError.geocodingFailed
        }

        guard let mapItem = mapItems.first else {
            throw UserLocationError.geocodingFailed
        }

        // Bevorzugt: strukturierter Stadtname aus MKAddressRepresentations.
        if let city = sanitizedCityName(from: mapItem.addressRepresentations?.cityName) {
            return city
        }

        // Fallback: Stadt mit Kontext (z. B. „Berlin, Deutschland“ → „Berlin“).
        if let cityWithContext = mapItem.addressRepresentations?.cityWithContext,
           let city = sanitizedCityName(from: firstAddressComponent(cityWithContext)) {
            return city
        }

        // Letzter Fallback: Ortsname aus dem MapKit-Ergebnis.
        if let name = sanitizedCityName(from: mapItem.name) {
            return name
        }

        throw UserLocationError.geocodingFailed
    }

    /// Trimmt und prüft einen Stadtnamen auf Leerheit.
    private func sanitizedCityName(from raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Extrahiert den ersten Teil vor einem Komma (Stadt vor Region/Land).
    private func firstAddressComponent(_ value: String) -> String {
        value.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }
}
