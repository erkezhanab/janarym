import CoreLocation
import MapKit

@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published var location: CLLocation?
    @Published var address: String = ""
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var geocodeTask: Task<Void, Never>?

    var isGranted: Bool {
        authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        authStatus = manager.authorizationStatus
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        geocodeTask?.cancel()
    }

    // MARK: - Nearby search (MKLocalSearch)

    func searchNearby(_ query: String, radiusMeters: Double = 1000) async -> String {
        guard let loc = location else {
            return "Орналасу белгісіз."
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: loc.coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return "Іздеу нәтижесі табылмады."
        }

        let items = response.mapItems.prefix(5)
        var lines: [String] = []
        for (i, item) in items.enumerated() {
            let name = item.name ?? "Белгісіз"
            var parts = [name]
            if let itemLoc = item.placemark.location {
                let dist = loc.distance(from: itemLoc)
                let distStr = dist < 1000
                    ? "\(Int(dist)) м"
                    : String(format: "%.1f км", dist / 1000)
                parts.append(distStr)
            }
            if let street = item.placemark.thoroughfare {
                parts.append(street)
            }
            lines.append("\(i + 1). \(parts.joined(separator: " — "))")
        }
        return lines.isEmpty ? "Жақын жерде табылмады." : lines.joined(separator: "\n")
    }

    // MARK: - Walking route (MKDirections)

    func buildWalkingRoute(to destination: String) async -> String {
        guard let loc = location else { return "Орналасу белгісіз." }

        let searchReq = MKLocalSearch.Request()
        searchReq.naturalLanguageQuery = destination
        searchReq.region = MKCoordinateRegion(
            center: loc.coordinate,
            latitudinalMeters: 15_000,
            longitudinalMeters: 15_000
        )
        guard let searchResp = try? await MKLocalSearch(request: searchReq).start(),
              let dest = searchResp.mapItems.first else {
            return "'\(destination)' табылмады."
        }

        let dirReq = MKDirections.Request()
        dirReq.source = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        dirReq.destination = dest
        dirReq.transportType = .walking

        guard let dirResp = try? await MKDirections(request: dirReq).calculate(),
              let route = dirResp.routes.first else {
            return "'\(destination)' дейін маршрут табылмады."
        }

        let distStr = route.distance < 1000
            ? "\(Int(route.distance)) метр"
            : String(format: "%.1f км", route.distance / 1000)
        let minStr = "\(Int(route.expectedTravelTime / 60)) минут"

        var lines = ["\(dest.name ?? destination) дейін: \(distStr), шамамен \(minStr) жаяу."]
        for (i, step) in route.steps.enumerated() where !step.instructions.isEmpty {
            let d = step.distance > 0 ? " (\(Int(step.distance)) м)" : ""
            lines.append("\(i + 1). \(step.instructions)\(d)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Location context for voice assistant

    var locationContext: String {
        guard let loc = location else { return "" }
        let lat = String(format: "%.5f", loc.coordinate.latitude)
        let lon = String(format: "%.5f", loc.coordinate.longitude)
        var ctx = "[Навигация контексті] Пайдаланушының қазіргі орналасуы:"
        if !address.isEmpty { ctx += " \(address)." }
        ctx += " GPS координаттары: \(lat), \(lon)."
        ctx += " Пайдаланушыға навигация, жақын жерлер, маршрут туралы нақты аудио нұсқаулар бер."
        return ctx
    }

    // MARK: - Private

    private func reverseGeocode(_ location: CLLocation) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            let geocoder = CLGeocoder()
            guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
                  let p = placemarks.first else { return }
            guard !Task.isCancelled else { return }
            let components = [p.name, p.thoroughfare, p.subLocality, p.locality]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            self.address = components.prefix(3).joined(separator: ", ")
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
}
