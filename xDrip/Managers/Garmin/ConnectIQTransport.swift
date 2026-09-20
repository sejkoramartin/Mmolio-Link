import Foundation
import OSLog

#if canImport(ConnectIQ)
import ConnectIQ

final class ConnectIQTransport: NSObject, GarminTransport {
    /// Kept compatible with the receiver app already used by MedProbe while the
    /// xDrip-specific Garmin app/watch face is being developed.
    static let watchAppID = "a1b2c3d4e5f647589a0b1c2d3e4f5061"

    static var watchAppUUID: UUID? {
        ConnectIQAppID.uuid(from: watchAppID)
    }

    static let returnURLScheme = "xdrip-garmin"

    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: "Garmin")

    private(set) var devices: [GarminDevice] = [] {
        didSet { notifyStateChanged() }
    }
    private(set) var selectedDevice: GarminDevice? {
        didSet { notifyStateChanged() }
    }
    private(set) var lastSentAt: Date? {
        didSet { notifyStateChanged() }
    }
    private(set) var lastError: GarminTransportError? {
        didSet { notifyStateChanged() }
    }

    private var policy = GarminSendPolicy()
    private var knownDevices: [UInt64: IQDevice] = [:]
    private var watchApps: [UInt64: IQApp] = [:]

    private static let selectedDeviceKey = "garminWatch.selectedDevice"
    private static let knownDevicesKey = "garminWatch.knownDevices"

    func start() {
        ConnectIQ.sharedInstance().initialize(
            withUrlScheme: Self.returnURLScheme,
            uiOverrideDelegate: nil,
            stateRestorationIdentifier: (Bundle.main.bundleIdentifier ?? "xdripswift") + ".garmin.connectiq"
        )
        restoreKnownDevices()
    }

    func stop() {
        for device in knownDevices.values {
            ConnectIQ.sharedInstance().unregister(forDeviceEvents: device, delegate: self)
        }
        for app in watchApps.values {
            ConnectIQ.sharedInstance().unregister(forAppMessages: app, delegate: self)
        }
    }

    func requestDevices() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    func handleReturn(from url: URL) {
        guard let returned = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice] else {
            return
        }

        trace("Garmin device selection returned %{public}@ device(s)", log: log, category: "Garmin", type: .info, returned.count.description)
        register(returned)
    }

    func select(_ device: GarminDevice?) {
        selectedDevice = device
        UserDefaults.standard.set(Int64(bitPattern: device?.id ?? 0), forKey: Self.selectedDeviceKey)
        policy.reset()
    }

    func send(_ reading: GarminGlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        switch policy.decide(reading) {
        case .skipDuplicate, .skipOlder:
            completion(.success(()))
            return
        case .send:
            break
        }

        guard let selectedDevice else {
            fail(.noDeviceSelected, completion)
            return
        }
        guard let device = knownDevices[selectedDevice.id],
              let app = watchApps[selectedDevice.id] else {
            fail(.appNotInstalled, completion)
            return
        }
        guard ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected else {
            fail(.deviceNotConnected, completion)
            return
        }

        ConnectIQ.sharedInstance().sendMessage(
            GarminMessage(reading: reading).encoded(),
            to: app,
            progress: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                if result == .success {
                    self.lastSentAt = Date()
                    self.lastError = nil
                    completion(.success(()))
                } else {
                    self.policy.reset()
                    self.fail(.sendFailed(Self.describe(result)), completion)
                }
            }
        }
    }

    private static func identity(of device: IQDevice) -> UInt64 {
        withUnsafeBytes(of: device.uuid.uuid) { raw in
            raw.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
    }

    private func restoreKnownDevices() {
        guard let stored = UserDefaults.standard.array(forKey: Self.knownDevicesKey) as? [[String: String]] else {
            return
        }

        let restored = stored.compactMap { entry -> IQDevice? in
            guard let uuidString = entry["uuid"],
                  let uuid = UUID(uuidString: uuidString) else {
                return nil
            }

            return IQDevice(
                id: uuid,
                modelName: entry["model"] ?? "",
                friendlyName: entry["name"] ?? "Garmin"
            )
        }

        if !restored.isEmpty {
            register(restored)
        }
    }

    private func rememberKnownDevices() {
        let entries = knownDevices.values.map { device in
            [
                "uuid": device.uuid.uuidString,
                "model": device.modelName ?? "",
                "name": device.friendlyName ?? "Garmin"
            ]
        }
        UserDefaults.standard.set(entries, forKey: Self.knownDevicesKey)
    }

    private func register(_ found: [IQDevice]) {
        for device in found {
            let id = Self.identity(of: device)
            knownDevices[id] = device
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)

            guard let appUUID = Self.watchAppUUID else {
                lastError = .sendFailed("Invalid Connect IQ application identifier.")
                continue
            }

            if let app = IQApp(uuid: appUUID, store: nil, device: device) {
                watchApps[id] = app
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
            }
        }

        rememberKnownDevices()
        refreshDeviceList()

        let storedID = UInt64(bitPattern: Int64(UserDefaults.standard.integer(forKey: Self.selectedDeviceKey)))
        if selectedDevice == nil, storedID != 0 {
            selectedDevice = devices.first { $0.id == storedID }
        }

        if selectedDevice == nil, devices.count == 1, let only = devices.first {
            select(only)
        }
    }

    private func refreshDeviceList() {
        devices = knownDevices.map { id, device in
            GarminDevice(
                id: id,
                name: device.friendlyName ?? device.modelName ?? "Garmin",
                isConnected: ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected
            )
        }
        .sorted { $0.name < $1.name }

        if let selected = selectedDevice,
           let refreshed = devices.first(where: { $0.id == selected.id }) {
            selectedDevice = refreshed
        }
    }

    private func fail(_ error: GarminTransportError,
                      _ completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        lastError = error
        trace("Garmin: %{public}@", log: log, category: "Garmin", type: .error, error.userFacingDescription)
        completion(.failure(error))
    }

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .garminWatchStateDidChange, object: nil)
        }
    }

    static func describe(_ result: IQSendMessageResult) -> String {
        switch result {
        case .success: return "sent"
        case .failure_Unknown: return "unknown error"
        case .failure_InternalError: return "internal SDK error"
        case .failure_DeviceNotAvailable: return "watch not available"
        case .failure_AppNotFound: return "receiver app not found on watch"
        case .failure_DeviceIsBusy: return "watch is busy"
        case .failure_UnsupportedType: return "unsupported message type"
        case .failure_InsufficientMemory: return "watch is out of memory"
        case .failure_Timeout: return "timed out"
        case .failure_MaxRetries: return "maximum retries reached"
        case .failure_PromptNotDisplayed: return "watch ignored the message"
        case .failure_AppAlreadyRunning: return "receiver app already running"
        @unknown default: return "Connect IQ result \(result.rawValue)"
        }
    }
}

extension ConnectIQTransport: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        refreshDeviceList()
    }
}

extension ConnectIQTransport: IQAppMessageDelegate {
    func receivedMessage(_ message: Any, from app: IQApp) {
        // Current protocol is phone -> watch only.
    }
}

#else

final class ConnectIQTransport: UnavailableGarminTransport {}

#endif

extension Notification.Name {
    static let garminWatchStateDidChange = Notification.Name("garminWatchStateDidChange")
}
