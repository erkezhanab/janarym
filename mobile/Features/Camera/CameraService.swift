import AVFoundation
import CoreImage
import Photos
import UIKit

final class CameraService: NSObject, ObservableObject {

    @Published var isRunning  = false
    @Published var isStarting = false   // UI overlay үшін
    @Published var error: AppError?
    @Published private(set) var isVideoRecording = false
    @Published private(set) var lastRecordedVideoURL: URL?

    let session = AVCaptureSession()

    private let sessionQueue  = DispatchQueue(label: "com.janarym.camera")
    private var isConfigured   = false
    private var sessionStarting = false  // sessionQueue-дағы internal flag
    private var retryCount    = 0
    private let maxRetries    = 2
    private var timeoutWork: DispatchWorkItem?

    private var activeVideoDevice: AVCaptureDevice?

    // MARK: - Frame capture (Vision үшін)
    private let frameOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let frameLock   = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private lazy var frameCIContext: CIContext = {
        // On Apple Silicon Macs running the iPhone app, Core Image + camera buffers
        // can trip Metal validation/assertions. Use the software renderer there.
        let useSoftwareRenderer = ProcessInfo.processInfo.isiOSAppOnMac
        return CIContext(options: [.useSoftwareRenderer: useSoftwareRenderer])
    }()

    // MARK: - Auto torch (frame brightness негізінде)
    var autoTorchEnabled = false
    private var torchFrameCounter = 0
    private var currentTorchState = false
    private var manualTorchOverride: Bool?

    // MARK: - Video recording
    private let maxVideoDuration: TimeInterval = 15
    private var currentRecordingURL: URL?
    private var isVideoRecordingPending = false
    private var pendingStopAfterRecordingStarts = false
    private var recordingStartTimeoutWork: DispatchWorkItem?

    override init() {
        super.init()
        observeSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Frame capture public API

    func captureCurrentFrameJPEG(maxEdge: CGFloat = 512) -> Data? {
        frameLock.lock()
        let buffer = latestPixelBuffer
        frameLock.unlock()
        guard let buffer else { return nil }
        return encodeJPEG(from: buffer, maxEdge: maxEdge, compressionQuality: 0.65)
    }

    func captureCurrentFrameBase64(maxEdge: CGFloat = 768) -> String? {
        frameLock.lock()
        let buffer = latestPixelBuffer
        frameLock.unlock()
        guard let buffer,
              let jpeg = encodeJPEG(from: buffer, maxEdge: maxEdge, compressionQuality: 0.6) else { return nil }
        return jpeg.base64EncodedString()
    }

    private func encodeJPEG(from pixelBuffer: CVPixelBuffer,
                            maxEdge: CGFloat,
                            compressionQuality: CGFloat) -> Data? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let extent = sourceImage.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }

        let clampedEdge = max(1, maxEdge)
        let scale = min(clampedEdge / max(extent.width, extent.height), 1.0)
        let outputImage: CIImage
        if scale < 0.999 {
            outputImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            outputImage = sourceImage
        }

        let finalImage = outputImage.cropped(to: outputImage.extent.integral)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return frameCIContext.jpegRepresentation(
            of: finalImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: compressionQuality]
        )
    }

    // MARK: - Session control

    func start() {
        DispatchQueue.main.async {
            self.error = nil
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                } else {
                    DispatchQueue.main.async {
                        self?.error = .permissionDenied("Камера")
                    }
                }
            }
        default:
            DispatchQueue.main.async { self.error = .permissionDenied("Камера") }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.sessionStarting else { return }

            self.sessionStarting = true
            DispatchQueue.main.async { self.isStarting = true }
            self.scheduleStartupTimeout()

            if !self.isConfigured {
                self.configureSession()
            }

            // configureSession сәтсіз болса — тоқта
            guard self.isConfigured else {
                self.finishStart(running: false)
                return
            }

            if !self.session.isRunning {
                // startRunning() is a synchronous blocking call that can take
                // 5–10 s on first launch after permission grant (hardware init).
                // It must NOT be called from the main thread; sessionQueue is correct.
                self.session.startRunning()
            }

            self.finishStart(running: self.session.isRunning)
        }
    }

    private func scheduleStartupTimeout() {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRunning else { return }
            // Timeout fired while startRunning() is still blocking on sessionQueue.
            // Dispatch stopRunning() on sessionQueue so it runs AFTER startRunning()
            // finishes (or immediately if already stuck). Then reset flags and retry.
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.session.isRunning { self.session.stopRunning() }
                self.sessionStarting = false
                self.isConfigured = false
                DispatchQueue.main.async {
                    self.isStarting = false
                    guard self.retryCount < self.maxRetries else {
                        self.retryCount = 0
                        self.error = .cameraUnavailable
                        return
                    }
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.start()
                    }
                }
            }
        }
        timeoutWork = work
        // 10 s: first-ever camera init after permission grant can legitimately take 5–8 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func finishStart(running: Bool) {
        DispatchQueue.main.async {
            self.timeoutWork?.cancel()
            self.timeoutWork = nil
            self.sessionStarting = false
            self.isStarting  = false
            self.retryCount  = 0
            self.isRunning   = running
            self.error       = running ? nil : .cameraUnavailable
        }
    }

    func stop() {
        timeoutWork?.cancel()
        timeoutWork = nil
        recordingStartTimeoutWork?.cancel()
        recordingStartTimeoutWork = nil
        retryCount = 0
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.sessionStarting = false
            self.isVideoRecordingPending = false
            self.pendingStopAfterRecordingStarts = false
            DispatchQueue.main.async { self.isStarting = false }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if self.currentTorchState {
                self.setTorchState(on: false)
                self.currentTorchState = false
            }
            self.manualTorchOverride = nil
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            DispatchQueue.main.async { self.error = .permissionDenied("Камера") }
            return
        }

        // Егер бұрын конфигурацияланған болса — қайта жасамау
        if isConfigured { return }

        session.beginConfiguration()
        resetSessionGraphLocked()

        // .high барлық iPhone-да жұмыс жасамайды — fallback .medium
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        // Камера құрылғысы
        guard let device = preferredVideoDevice() else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }
        activeVideoDevice = device

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }
        session.addInput(input)

        // Frame output — Vision үшін
        frameOutput.alwaysDiscardsLateVideoFrames = true
        frameOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frameOutput.setSampleBufferDelegate(
            self,
            queue: DispatchQueue(label: "com.janarym.frame", qos: .utility)
        )
        if session.canAddOutput(frameOutput) {
            session.addOutput(frameOutput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.movieFragmentInterval = .invalid
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private func resetSessionGraphLocked() {
        session.inputs.forEach { session.removeInput($0) }
        frameOutput.setSampleBufferDelegate(nil, queue: nil)
        session.outputs.forEach { session.removeOutput($0) }
        activeVideoDevice = nil
        frameLock.lock()
        previousPixelBuffer = nil
        latestPixelBuffer = nil
        frameLock.unlock()
        torchFrameCounter = 0
        currentTorchState = false
        manualTorchOverride = nil
        currentRecordingURL = nil
        isVideoRecordingPending = false
        pendingStopAfterRecordingStarts = false
        recordingStartTimeoutWork?.cancel()
        recordingStartTimeoutWork = nil
    }

    private func preferredVideoDevice() -> AVCaptureDevice? {
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return back
        }
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - Torch

    func setTorch(on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.manualTorchOverride = on
            self.setTorchState(on: on)
        }
    }

    private func applyTorchOnSessionQueue(on: Bool) {
        sessionQueue.async { [weak self] in
            self?.setTorchState(on: on)
        }
    }

    var currentBrightness: Float {
        guard let device = activeVideoDevice ?? preferredVideoDevice() else { return 1 }
        let iso    = device.iso
        let maxISO = device.activeFormat.maxISO
        return max(0, min(1, 1.0 - (iso / maxISO)))
    }

    private func setTorchState(on: Bool) {
        guard let device = activeVideoDevice ?? preferredVideoDevice(),
              device.hasTorch, device.isTorchAvailable else { return }
        let previousState = currentTorchState
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            currentTorchState = on
            if previousState != on {
                DispatchQueue.main.async { [weak self] in
                    self?.onTorchChanged?(on)
                }
            }
        } catch {}
    }

    // MARK: - Video recording

    var onVideoRecordingChanged: ((Bool) -> Void)?
    var onVideoSaved: ((URL) -> Void)?
    var onVideoRecordingFailed: ((String) -> Void)?

    func startVideoRecording() {
        sessionQueue.async { [weak self] in
            self?.startVideoRecordingLocked()
        }
    }

    func stopVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
                return
            }

            if self.isVideoRecordingPending {
                self.pendingStopAfterRecordingStarts = true
                return
            }

            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(AppText.pick("Қазір видео түсіріліп жатқан жоқ",
                                                          "Сейчас видео не записывается"))
            }
        }
    }

    private func startVideoRecordingLocked() {
        if movieOutput.isRecording || isVideoRecordingPending {
            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(AppText.pick("Видео түсіріп жатырмын",
                                                          "Видео уже записывается"))
            }
            return
        }

        if !isConfigured {
            configureSession()
        }

        guard isConfigured else {
            isVideoRecordingPending = false
            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(AppError.cameraUnavailable.localizedDescription)
            }
            return
        }

        if !session.isRunning {
            session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
            }
        }

        guard movieOutput.connection(with: .video) != nil else {
            isVideoRecordingPending = false
            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(AppText.pick("Видео түсіруді бастай алмадым",
                                                          "Не удалось начать запись видео"))
            }
            return
        }

        let fileURL = nextVideoFileURL()
        try? FileManager.default.removeItem(at: fileURL)

        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported,
               activeVideoDevice?.position == .front {
                connection.isVideoMirrored = true
            }
        }

        movieOutput.maxRecordedDuration = CMTime(seconds: maxVideoDuration, preferredTimescale: 600)
        currentRecordingURL = fileURL
        isVideoRecordingPending = true
        pendingStopAfterRecordingStarts = false
        scheduleRecordingStartTimeout()
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
    }

    private func scheduleRecordingStartTimeout() {
        recordingStartTimeoutWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isVideoRecordingPending, !self.movieOutput.isRecording else { return }

            self.isVideoRecordingPending = false
            self.pendingStopAfterRecordingStarts = false
            self.currentRecordingURL = nil

            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(AppText.pick("Видео түсіру басталмады",
                                                          "Запись видео не началась"))
            }
        }

        recordingStartTimeoutWork = work
        sessionQueue.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func clearRecordingStartState() {
        recordingStartTimeoutWork?.cancel()
        recordingStartTimeoutWork = nil
        isVideoRecordingPending = false
    }

    private func recordingFinishedSuccessfully(with error: Error?) -> Bool {
        guard let error else { return true }

        let nsError = error as NSError
        if let finished = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            return finished
        }

        return false
    }

    private func nextVideoFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "janarym-video-\(formatter.string(from: Date())).mov"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func saveVideoToPhotoLibrary(_ fileURL: URL,
                                         completion: @escaping (Result<Void, Error>) -> Void) {
        let performSave = {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? NSError(
                            domain: "CameraService",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to save video to photo library"]
                        )))
                    }
                }
            }
        }

        if #available(iOS 14, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                performSave()
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    if status == .authorized || status == .limited {
                        performSave()
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(
                                domain: "CameraService",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]
                            )))
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "CameraService",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]
                    )))
                }
            }
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                performSave()
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        performSave()
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(
                                domain: "CameraService",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]
                            )))
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "CameraService",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]
                    )))
                }
            }
        }
    }

    // MARK: - Runtime recovery

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    @objc
    private func handleSessionRuntimeError(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isConfigured    = false
            self.sessionStarting     = false
            self.activeVideoDevice = nil
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isStarting = false
                self.isRunning  = false
                // Auto-retry on runtime error
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.start()
                    }
                } else {
                    self.retryCount = 0
                    self.error = .cameraUnavailable
                }
            }
        }
    }

    @objc
    private func handleSessionWasInterrupted(_ notification: Notification) {
        _ = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
    }

    @objc
    private func handleSessionInterruptionEnded(_ notification: Notification) {
        start()
    }

    // MARK: - Torch change callback

    /// Called on main thread when auto-torch switches on or off.
    var onTorchChanged: ((Bool) -> Void)?

    // MARK: - Motion detection

    var onMotionDetected: (() -> Void)?
    private var previousPixelBuffer: CVPixelBuffer?
    private var lastMotionTime: CFAbsoluteTime = 0
    private let motionCooldown: CFAbsoluteTime = 0.8
    private let motionThreshold: Float = 0.018

    private func checkMotion(current: CVPixelBuffer, previous: CVPixelBuffer?) {
        guard onMotionDetected != nil else { return }
        guard let previous else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMotionTime >= motionCooldown else { return }

        CVPixelBufferLockBaseAddress(current,  .readOnly)
        CVPixelBufferLockBaseAddress(previous, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(current,  .readOnly)
            CVPixelBufferUnlockBaseAddress(previous, .readOnly)
        }

        let width  = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        guard let curBase  = CVPixelBufferGetBaseAddress(current),
              let prevBase = CVPixelBufferGetBaseAddress(previous) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(current)
        let stepX = max(1, width  / 24)
        let stepY = max(1, height / 24)
        var diffSum: Float = 0
        var count = 0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x * 4
                let cur  = curBase .advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                let prev = prevBase.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                let diff = (abs(Float(cur[0]) - Float(prev[0])) +
                            abs(Float(cur[1]) - Float(prev[1])) +
                            abs(Float(cur[2]) - Float(prev[2]))) / (255.0 * 3.0)
                diffSum += diff
                count   += 1
                x += stepX
            }
            y += stepY
        }

        guard count > 0, (diffSum / Float(count)) > motionThreshold else { return }
        lastMotionTime = now
        onMotionDetected?()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameLock.lock()
        let previousForMotion = previousPixelBuffer
        latestPixelBuffer = pixelBuffer
        previousPixelBuffer = pixelBuffer
        frameLock.unlock()

        checkMotion(current: pixelBuffer, previous: previousForMotion)

        // Auto-torch: ~2 секунд сайын (30fps × 60 frame = 2s)
        // Hysteresis: ON threshold = 0.09, OFF threshold = 0.35
        // Prevents torch from flickering when it illuminates the scene.
        if autoTorchEnabled, manualTorchOverride == nil {
            torchFrameCounter += 1
            if torchFrameCounter % 60 == 0 {
                let brightness = frameBrightness(pixelBuffer)
                let shouldBeOn: Bool
                if currentTorchState {
                    // Currently ON → only turn OFF when scene is bright enough
                    shouldBeOn = brightness < 0.35
                } else {
                    // Currently OFF → only turn ON when scene is genuinely dark
                    shouldBeOn = brightness < 0.09
                }
                if shouldBeOn != currentTorchState {
                    applyTorchOnSessionQueue(on: shouldBeOn)
                }
            }
        }
    }

    private func frameBrightness(_ buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 1 }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let stepX = max(1, w / 20)
        let stepY = max(1, h / 20)
        var sum: Float = 0
        var n = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let p = base.advanced(by: y * bpr + x * 4).assumingMemoryBound(to: UInt8.self)
                sum += Float(p[0]) * 0.114 + Float(p[1]) * 0.587 + Float(p[2]) * 0.299
                n += 1
                x += stepX
            }
            y += stepY
        }
        return n > 0 ? (sum / Float(n)) / 255.0 : 1.0
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        clearRecordingStartState()
        let shouldStopImmediately = pendingStopAfterRecordingStarts
        pendingStopAfterRecordingStarts = false

        DispatchQueue.main.async {
            self.isVideoRecording = true
            self.onVideoRecordingChanged?(true)
        }

        if shouldStopImmediately {
            sessionQueue.async { [weak self] in
                guard let self, self.movieOutput.isRecording else { return }
                self.movieOutput.stopRecording()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        clearRecordingStartState()
        pendingStopAfterRecordingStarts = false
        currentRecordingURL = nil

        DispatchQueue.main.async {
            self.isVideoRecording = false
            self.onVideoRecordingChanged?(false)
        }

        guard recordingFinishedSuccessfully(with: error) else {
            DispatchQueue.main.async {
                self.onVideoRecordingFailed?(JanarymVoice.shared.videoFailed())
            }
            return
        }

        saveVideoToPhotoLibrary(outputFileURL) { result in
            self.lastRecordedVideoURL = outputFileURL
            switch result {
            case .success:
                self.onVideoSaved?(outputFileURL)
            case .failure:
                let message = AppText.pick(
                    "Видео түсірілді, бірақ галереяға сақтай алмадым",
                    "Видео записалось, но не удалось сохранить в галерею"
                )
                self.onVideoRecordingFailed?(message)
            }
        }
    }
}
