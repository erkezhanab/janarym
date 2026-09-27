import Combine
import CoreBluetooth
import Foundation

/// Fetches JPEG frames from the ESP32-CAM glasses module over local WiFi.
/// Prefers MJPEG stream (/stream) for smooth live preview; falls back to
/// snapshot polling (/snapshot) if the stream connection drops.
///
/// Local Network permission: iOS 14+ automatically shows the system dialog on
/// the first HTTP request to a local IP — no manual NWBrowser trigger needed.
@MainActor
final class ESP32CameraService: NSObject, ObservableObject {

    enum ConnectionIssue: Equatable {
        case localNetworkDenied
        case appTransportBlocked
        case timedOut
        case unreachable
        case invalidResponse
        case unknown
    }

    static let hostDefaultsKey = "esp32_camera_host"
    static let peripheralDefaultsKey = "esp32_camera_ble_peripheral"
    static let defaultHost = "192.168.43.230"
    private static let bleServiceUUID = CBUUID(string: "7A0247E7-7E88-4B71-9A5D-E3A8A4D31F01")
    private static let bleHostCharacteristicUUID = CBUUID(string: "7A0247E7-7E88-4B71-9A5D-E3A8A4D31F02")

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var latestSnapshot: Data? = nil
    @Published private(set) var lastSnapshotAt: Date? = nil
    @Published private(set) var host: String
    @Published private(set) var connectionIssue: ConnectionIssue? = nil
    @Published private(set) var isDiscoveringViaBluetooth: Bool = false

    private var snapshotURL: URL
    private var streamURL: URL
    private var pollTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var bluetoothTimeoutTask: Task<Void, Never>?
    private var centralManager: CBCentralManager?
    private var discoveryPeripheral: CBPeripheral?
    private var shouldStartBluetoothDiscovery = false
    private var preferredPollingIntervalMs: UInt64 = 300
    private var pollingStartedAt: Date? = nil
    private var isRestartingPolling = false
    private var consecutiveFailures = 0
    private let failureTolerance = 3
    private let firstFrameTimeout: TimeInterval = 4.5
    private let staleFrameTimeout: TimeInterval = 3.2

    // URLSession for snapshot fallback (short timeout)
    private let snapshotSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 4
        cfg.timeoutIntervalForResource = 4
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    // URLSession for MJPEG stream (no resource timeout — stream is long-lived)
    private let streamSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 5
        cfg.timeoutIntervalForResource = .infinity
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    init(host: String? = nil) {
        let endpoints = Self.makeEndpoints(from: host ?? Self.storedHost())
        self.host = endpoints.displayHost
        self.snapshotURL = endpoints.snapshotURL
        self.streamURL = endpoints.streamURL
        super.init()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSavedHostIfNeeded()
            }
        }
    }

    deinit {
        pollTask?.cancel()
        watchdogTask?.cancel()
        bluetoothTimeoutTask?.cancel()
        centralManager?.stopScan()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - Snapshot (single fetch)

    /// Returns JPEG data from the ESP32-CAM, or nil if unreachable.
    /// Updates `isConnected` and `latestSnapshot` as a side-effect.
    func fetchSnapshot() async -> Data? {
        do {
            let (data, response) = try await snapshotSession.data(for: Self.authorized(URLRequest(url: snapshotURL)))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count > 1000 else {
                registerFailure(.invalidResponse)
                return nil
            }
            consecutiveFailures = 0
            isConnected = true
            latestSnapshot = data
            lastSnapshotAt = Date()
            connectionIssue = nil
            return data
        } catch {
            registerFailure(Self.mapConnectionIssue(error))
            return nil
        }
    }

    // MARK: - Polling (MJPEG stream → snapshot fallback)

    /// Starts live preview: tries MJPEG stream first, falls back to snapshot polling.
    /// iOS 14+ shows the Local Network permission dialog automatically on the
    /// first HTTP request to a local IP — no manual permission trigger needed.
    func startPolling(intervalMs: UInt64 = 300) {
        pollTask?.cancel()
        watchdogTask?.cancel()
        preferredPollingIntervalMs = intervalMs
        pollingStartedAt = Date()
        connectionIssue = nil
        pollTask = Task { [weak self] in
            guard let self else { return }

            // Try MJPEG stream first
            let streamSucceeded = await self.runMJPEGStream()
            guard !Task.isCancelled else { return }

            // Fall back to snapshot polling if stream failed/ended
            if !streamSucceeded {
                await self.runSnapshotPolling(intervalMs: intervalMs)
            }
        }
        startWatchdog(intervalMs: intervalMs)
    }

    func discoverHostViaBluetooth() {
        guard !isDiscoveringViaBluetooth else { return }
        shouldStartBluetoothDiscovery = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
        guard centralManager?.state == .poweredOn else { return }
        beginBluetoothDiscovery()
    }

    func stopPolling(preserveLatestFrame: Bool = false) {
        pollTask?.cancel()
        watchdogTask?.cancel()
        pollTask = nil
        watchdogTask = nil
        pollingStartedAt = nil
        isConnected = false
        if !preserveLatestFrame {
            latestSnapshot = nil
            lastSnapshotAt = nil
            connectionIssue = nil
        }
        consecutiveFailures = 0
    }

    private func beginBluetoothDiscovery() {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        shouldStartBluetoothDiscovery = false
        bluetoothTimeoutTask?.cancel()
        discoveryPeripheral = nil
        isDiscoveringViaBluetooth = true
        if restoreKnownPeripheral(using: centralManager) {
            return
        }
        startScanning(using: centralManager)
        bluetoothTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard let self, self.isDiscoveringViaBluetooth else { return }
            self.finishBluetoothDiscovery()
        }
    }

    private func startScanning(using centralManager: CBCentralManager) {
        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: [Self.bleServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func restoreKnownPeripheral(using centralManager: CBCentralManager) -> Bool {
        if let remembered = Self.storedPeripheralID(),
           let peripheral = centralManager.retrievePeripherals(withIdentifiers: [remembered]).first {
            discoveryPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
            return true
        }

        if let connected = centralManager.retrieveConnectedPeripherals(withServices: [Self.bleServiceUUID]).first {
            discoveryPeripheral = connected
            connected.delegate = self
            centralManager.connect(connected, options: nil)
            return true
        }

        return false
    }

    private func finishBluetoothDiscovery() {
        bluetoothTimeoutTask?.cancel()
        bluetoothTimeoutTask = nil
        centralManager?.stopScan()
        if let discoveryPeripheral {
            centralManager?.cancelPeripheralConnection(discoveryPeripheral)
        }
        discoveryPeripheral = nil
        isDiscoveringViaBluetooth = false
    }

    private func applyDiscoveredBluetoothHost(_ rawValue: String) {
        let endpoints = Self.makeEndpoints(from: rawValue)
        UserDefaults.standard.set(endpoints.displayHost, forKey: Self.hostDefaultsKey)
        if let identifier = discoveryPeripheral?.identifier.uuidString {
            UserDefaults.standard.set(identifier, forKey: Self.peripheralDefaultsKey)
        }
        applyEndpoints(endpoints)
        connectionIssue = nil
        finishBluetoothDiscovery()
    }

    private func startWatchdog(intervalMs: UInt64) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                guard self.pollTask != nil else { continue }
                guard !self.isDiscoveringViaBluetooth else { continue }

                let now = Date()
                let timedOutBeforeFirstFrame: Bool = {
                    guard self.latestSnapshot == nil,
                          let pollingStartedAt = self.pollingStartedAt else { return false }
                    return now.timeIntervalSince(pollingStartedAt) > self.firstFrameTimeout
                }()
                let staleFrame: Bool = {
                    guard let lastSnapshotAt = self.lastSnapshotAt else { return false }
                    return now.timeIntervalSince(lastSnapshotAt) > self.staleFrameTimeout
                }()

                guard timedOutBeforeFirstFrame || staleFrame else { continue }
                let shouldRediscover = timedOutBeforeFirstFrame
                    || self.connectionIssue == .timedOut
                    || self.connectionIssue == .unreachable
                self.scheduleReconnect(intervalMs: intervalMs, rediscoverHost: shouldRediscover)
            }
        }
    }

    private func scheduleReconnect(intervalMs: UInt64, rediscoverHost: Bool) {
        guard !isRestartingPolling else { return }
        isRestartingPolling = true
        pollTask?.cancel()
        pollTask = nil
        isConnected = false
        if rediscoverHost {
            discoverHostViaBluetooth()
        }

        Task { @MainActor [weak self] in
            let delayNs: UInt64 = rediscoverHost ? 1_800_000_000 : 700_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard let self else { return }
            self.isRestartingPolling = false
            self.startPolling(intervalMs: intervalMs)
        }
    }

    // MARK: - MJPEG Stream

    /// Opens /stream and extracts JPEG frames from the multipart response.
    /// Returns true if stream started successfully (at least one frame received).
    private func runMJPEGStream() async -> Bool {
        var request = Self.authorized(URLRequest(url: streamURL))
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (asyncBytes, response) = try await streamSession.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                registerFailure(.invalidResponse)
                return false
            }

            var buffer = Data()
            var frameCount = 0
            let jpegStart: [UInt8] = [0xFF, 0xD8]
            let jpegEnd:   [UInt8] = [0xFF, 0xD9]

            for try await byte in asyncBytes {
                guard !Task.isCancelled else { return frameCount > 0 }
                buffer.append(byte)

                // Extract complete JPEG frames (FF D8 ... FF D9)
                if let frame = Self.extractJPEG(from: &buffer,
                                                start: jpegStart,
                                                end: jpegEnd),
                   frame.count > 1000 {
                    frameCount += 1
                    consecutiveFailures = 0
                    isConnected = true
                    latestSnapshot = frame
                    lastSnapshotAt = Date()
                    connectionIssue = nil
                }

                // Keep buffer bounded (≤ 200 KB)
                if buffer.count > 200_000 {
                    buffer.removeAll()
                }
            }
            return frameCount > 0
        } catch {
            if !Task.isCancelled {
                registerFailure(Self.mapConnectionIssue(error))
            }
            return false
        }
    }

    /// Extracts the first complete JPEG (FF D8 … FF D9) from `buffer`.
    private static func extractJPEG(from buffer: inout Data,
                                    start: [UInt8],
                                    end: [UInt8]) -> Data? {
        guard let startRange = buffer.range(of: Data(start)),
              let endRange   = buffer.range(of: Data(end),
                                            in: startRange.upperBound..<buffer.endIndex)
        else { return nil }

        let frameRange = startRange.lowerBound..<endRange.upperBound
        let frame = buffer.subdata(in: frameRange)
        buffer.removeSubrange(..<endRange.upperBound)
        return frame
    }

    // MARK: - Snapshot Polling (fallback)

    private func runSnapshotPolling(intervalMs: UInt64) async {
        while !Task.isCancelled {
            _ = await fetchSnapshot()
            try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
    }

    // MARK: - Host management

    func updateHost(_ newHost: String) {
        let endpoints = Self.makeEndpoints(from: newHost)
        UserDefaults.standard.set(endpoints.displayHost, forKey: Self.hostDefaultsKey)
        applyEndpoints(endpoints)
    }

    static func saveHost(_ rawValue: String) -> String {
        let endpoints = makeEndpoints(from: rawValue)
        UserDefaults.standard.set(endpoints.displayHost, forKey: hostDefaultsKey)
        return endpoints.displayHost
    }

    static func storedHost() -> String {
        let rawValue = UserDefaults.standard.string(forKey: hostDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue?.isEmpty == false ? rawValue! : defaultHost
    }

    private static func storedPeripheralID() -> UUID? {
        guard let rawValue = UserDefaults.standard.string(forKey: peripheralDefaultsKey),
              let uuid = UUID(uuidString: rawValue) else { return nil }
        return uuid
    }

    private func reloadSavedHostIfNeeded() {
        let endpoints = Self.makeEndpoints(from: Self.storedHost())
        guard host != endpoints.displayHost || snapshotURL != endpoints.snapshotURL || streamURL != endpoints.streamURL else {
            return
        }
        applyEndpoints(endpoints)
    }

    private func applyEndpoints(_ endpoints: Endpoints) {
        host = endpoints.displayHost
        snapshotURL = endpoints.snapshotURL
        streamURL = endpoints.streamURL
        latestSnapshot = nil
        lastSnapshotAt = nil
        isConnected = false
        connectionIssue = nil
        pollingStartedAt = nil
        consecutiveFailures = 0
        if pollTask != nil { startPolling() }
    }

    /// The camera rejects unauthenticated requests to /stream and /snapshot.
    private static func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        let token = AppConfig.esp32StreamToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private struct Endpoints {
        let displayHost: String
        let snapshotURL: URL
        let streamURL: URL
    }

    private static func makeEndpoints(from rawValue: String) -> Endpoints {
        let baseURL = normalizedBaseURL(from: rawValue)
        let displayHost = displayHost(from: baseURL)
        return Endpoints(
            displayHost: displayHost,
            snapshotURL: endpointURL(baseURL: baseURL, path: "snapshot"),
            streamURL: endpointURL(baseURL: baseURL, path: "stream")
        )
    }

    private static func normalizedBaseURL(from rawValue: String) -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? defaultHost : trimmed
        let candidate = seed.contains("://") ? seed : "http://\(seed)"
        let fallback = URL(string: "http://\(defaultHost)")!

        guard var components = URLComponents(string: candidate) else {
            return fallback
        }

        if components.path == "/snapshot" || components.path == "/stream" {
            components.path = ""
        } else if !components.path.isEmpty, components.path != "/" {
            components.path = ""
        }

        components.query = nil
        components.fragment = nil
        return components.url ?? fallback
    }

    private static func endpointURL(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appendingPathComponent(path)
        }
        components.path = "/\(path)"
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL.appendingPathComponent(path)
    }

    private static func displayHost(from url: URL) -> String {
        guard let host = url.host else { return defaultHost }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private static func mapConnectionIssue(_ error: Error) -> ConnectionIssue {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.appTransportSecurityRequiresSecureConnection.rawValue {
            return .appTransportBlocked
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timedOut
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return .unreachable
            case .dataNotAllowed:
                // iOS Local Network permission denied
                return .localNetworkDenied
            case .appTransportSecurityRequiresSecureConnection:
                return .appTransportBlocked
            default:
                break
            }
        }

        return .unknown
    }

    private func registerFailure(_ issue: ConnectionIssue) {
        consecutiveFailures += 1
        guard consecutiveFailures >= failureTolerance else { return }
        isConnected = false
        connectionIssue = issue
    }
}

extension ESP32CameraService: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if central.state == .poweredOn, self.shouldStartBluetoothDiscovery {
                self.beginBluetoothDiscovery()
            } else if central.state != .poweredOn {
                self.isDiscoveringViaBluetooth = false
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor [weak self] in
            guard let self, self.discoveryPeripheral == nil else { return }
            self.discoveryPeripheral = peripheral
            peripheral.delegate = self
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.peripheralDefaultsKey)
            central.stopScan()
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([Self.bleServiceUUID])
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }
            peripheral.services?.forEach { service in
                guard service.uuid == Self.bleServiceUUID else { return }
                peripheral.discoverCharacteristics([Self.bleHostCharacteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }
            service.characteristics?.forEach { characteristic in
                guard characteristic.uuid == Self.bleHostCharacteristicUUID else { return }
                peripheral.readValue(for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard error == nil,
                  characteristic.uuid == Self.bleHostCharacteristicUUID,
                  let data = characteristic.value,
                  let hostString = String(data: data, encoding: .utf8),
                  !hostString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.finishBluetoothDiscovery()
                return
            }
            self.applyDiscoveredBluetoothHost(hostString)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.discoveryPeripheral = nil
            self.startScanning(using: central)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.discoveryPeripheral?.identifier == peripheral.identifier else { return }
            self.discoveryPeripheral = nil
        }
    }
}
