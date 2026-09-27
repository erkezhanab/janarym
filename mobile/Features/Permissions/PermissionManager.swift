import AVFoundation
import Speech
import SwiftUI

final class PermissionManager: ObservableObject {

    @Published var cameraGranted = false
    @Published var microphoneGranted = false
    @Published var speechGranted = false
    @Published var allGranted = false

    private func updateAllGranted() {
        // allGranted only gates navigation on camera + mic. Speech is requested
        // eagerly but a denial shouldn't block the app — realtime service falls
        // back to Whisper transcription.
        let granted = cameraGranted && microphoneGranted
        if allGranted != granted {
            allGranted = granted
        }
    }

    func checkAll() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        updateAllGranted()
    }

    func requestAll() {
        requestCamera { [weak self] in
            self?.requestMicrophone {
                self?.requestSpeech { }
            }
        }
    }

    private func requestCamera(completion: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.cameraGranted = true
                self.updateAllGranted()
                completion()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraGranted = granted
                    self?.updateAllGranted()
                    completion()
                }
            }
        default:
            DispatchQueue.main.async {
                self.cameraGranted = false
                self.updateAllGranted()
                completion()
            }
        }
    }

    private func requestMicrophone(completion: @escaping () -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            DispatchQueue.main.async {
                self.microphoneGranted = true
                self.updateAllGranted()
                completion()
            }
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                    self?.updateAllGranted()
                    completion()
                }
            }
        default:
            DispatchQueue.main.async {
                self.microphoneGranted = false
                self.updateAllGranted()
                completion()
            }
        }
    }

    private func requestSpeech(completion: @escaping () -> Void) {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.speechGranted = true
                completion()
            }
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.speechGranted = (status == .authorized)
                    completion()
                }
            }
        default:
            DispatchQueue.main.async {
                self.speechGranted = false
                completion()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
