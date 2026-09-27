import Foundation
import CoreLocation
import UIKit

/// Member жағы: локация + батарея + соңғы фото → Firestore-ке жіберіп тұрады
final class UserPresenceService: NSObject {

    static let shared = UserPresenceService()

    private enum LiveTracking {
        static let timerInterval: TimeInterval = 10
        static let minUploadInterval: TimeInterval = 5
        static let forceUploadInterval: TimeInterval = 25
        static let minDistanceMeters: CLLocationDistance = 7
    }

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var photoTimer: Timer?
    private(set) var lastLocation: CLLocation?
    private var userId: String?
    private var lastUploadedPhotoURL: String?
    private var lastUploadedPhotoBase64: String?
    private var lastUploadedLocation: CLLocation?
    private var lastPresenceUploadAt: Date?
    private var didRequestAlwaysAuthorization = false

    /// AssistantCoordinator арқылы CameraService-ке қол жеткізу
    var capturePhoto: (() -> Data?)? = nil

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Public

    func start(userId: String) {
        self.userId = userId
        lastUploadedPhotoURL = nil
        lastUploadedPhotoBase64 = nil
        lastUploadedLocation = nil
        lastPresenceUploadAt = nil
        if locationManager.authorizationStatus == .authorizedWhenInUse && !didRequestAlwaysAuthorization {
            didRequestAlwaysAuthorization = true
            locationManager.requestAlwaysAuthorization()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()

        // Live tracking: frequent presence refresh while the child is moving.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: LiveTracking.timerInterval, repeats: true) { [weak self] _ in
            self?.uploadPresence(photoURL: nil)
        }
        uploadPresence(photoURL: nil)

        // 5 минут сайын соңғы камера кадрын Storage-ке жүктеу
        photoTimer?.invalidate()
        photoTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let data = self?.capturePhoto?() else { return }
            self?.uploadPhotoAndPresence(jpegData: data)
        }

        // Push one frame shortly after startup so the parent can see a photo
        // without waiting for the 5-minute timer or the first PTT cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self,
                  self.userId == userId,
                  let data = self.capturePhoto?() else { return }
            self.uploadPhotoAndPresence(jpegData: data)
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        photoTimer?.invalidate()
        photoTimer = nil
        lastUploadedPhotoURL = nil
        lastUploadedPhotoBase64 = nil
        lastUploadedLocation = nil
        lastPresenceUploadAt = nil
    }

    /// Камера кадрын жүктеп, presence-ті жаңарту
    func uploadPhotoAndPresence(jpegData: Data) {
        guard let uid = userId else { return }
        Task {
            let photoBase64 = jpegData.base64EncodedString()
            let url = await StorageService.shared.uploadLastPhoto(data: jpegData, userId: uid)
            self.lastUploadedPhotoBase64 = photoBase64
            if let url {
                self.lastUploadedPhotoURL = url
                let location = self.lastLocation?.coordinate
                let battery = await MainActor.run { max(0.0, Double(UIDevice.current.batteryLevel)) }
                await FirestoreService.shared.updateLastPhoto(
                    userId: uid,
                    photoURL: url,
                    photoBase64: photoBase64,
                    lat: location?.latitude,
                    lng: location?.longitude,
                    battery: location == nil ? nil : battery
                )
            } else {
                await FirestoreService.shared.updateLastPhoto(
                    userId: uid,
                    photoURL: nil,
                    photoBase64: photoBase64
                )
            }
            uploadPresence(photoURL: url, photoBase64: photoBase64)
        }
    }

    // MARK: - Private

    private func uploadPresence(photoURL: String?, photoBase64: String? = nil) {
        guard let uid = userId, let loc = lastLocation else { return }
        let resolvedPhotoURL = photoURL ?? lastUploadedPhotoURL
        let resolvedPhotoBase64 = photoBase64 ?? lastUploadedPhotoBase64
        lastUploadedLocation = loc
        lastPresenceUploadAt = Date()
        Task {
            let battery = await MainActor.run { max(0.0, Double(UIDevice.current.batteryLevel)) }
            await FirestoreService.shared.updatePresence(
                userId: uid,
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                battery: battery,
                photoURL: resolvedPhotoURL,
                photoBase64: resolvedPhotoBase64,
                accuracy: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil,
                speed: loc.speed >= 0 ? loc.speed : nil,
                heading: loc.course >= 0 ? loc.course : nil
            )
        }
    }

    private func shouldUploadLiveLocation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard let lastPresenceUploadAt else { return true }

        let elapsed = Date().timeIntervalSince(lastPresenceUploadAt)
        if elapsed >= LiveTracking.forceUploadInterval { return true }
        guard elapsed >= LiveTracking.minUploadInterval else { return false }

        guard let lastUploadedLocation else { return true }
        return location.distance(from: lastUploadedLocation) >= LiveTracking.minDistanceMeters
    }
}

extension UserPresenceService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        if shouldUploadLiveLocation(location) {
            uploadPresence(photoURL: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if manager.authorizationStatus == .authorizedWhenInUse && !didRequestAlwaysAuthorization {
                didRequestAlwaysAuthorization = true
                manager.requestAlwaysAuthorization()
            }
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
