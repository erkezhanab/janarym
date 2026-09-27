import AVFoundation

/// Singleton that sets up AVAudioSession ONCE at app launch.
/// Camera + mic + TTS all coexist using playAndRecord + mixWithOthers.
enum AudioSessionManager {

    enum Mode {
        case idle
        case recording
        case playback
    }

    private static func print(_ items: Any...) {}

    private static var currentMode: Mode?

    static func configure() {
        activate(.idle)
    }

    static func activate(_ mode: Mode, force: Bool = false) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                activate(mode, force: force)
            }
            return
        }
        guard force || currentMode != mode else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            switch mode {
            case .idle:
                // Do NOT call setActive(false, .notifyOthersOnDeactivation) here —
                // it blocks the main thread while waiting for SFSpeechRecognizer to
                // respond, which itself needs the main thread → deadlock → black screen
                // requiring phone reboot. Category change + setActive(true) is sufficient.
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
                )
                try session.setActive(true)
                try? session.overrideOutputAudioPort(.speaker)
                currentMode = mode
                return
            case .recording:
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetoothHFP]
                )
            case .playback:
                try session.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers]
                )
            }
            try session.setActive(true)
            currentMode = mode
        } catch {
            print("AudioSession: configure error \(error)")
        }
    }
}
