import Foundation
import OSLog

#if canImport(ConnectIQ)
import ConnectIQ

final class ConnectIQTransport: NSObject, GarminTransport {
    /// Existing Mmolio Bridge identity; never replace it with the data field ID.
    static let watchAppID = "a1b2c3d4e5f647589a0b1c2d3e4f5061"
    static let dataFieldAppID = "7ca56fd800634cab90f28d5e72be2e05"

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

    private lazy var delivery = GarminDeliveryQueue { [weak self] target, reading, completion in
        guard let self else {
            completion(.failure(.deviceNotConnected))
            return
        }
        self.transmit(reading, to: target, completion: completion)
    }
    private var selectionGeneration = 0
    private var knownDevices: [UInt64: IQDevice] = [:]
    private var watchApps: [UInt64: IQApp] = [:]
    private var dataFieldApps: [UInt64: IQApp] = [:]

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
        selectionGeneration += 1
        delivery.reset()
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
        selectionGeneration += 1
        delivery.reset()
    }

    func send(_ reading: GarminGlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [self] in send(reading, completion: completion) }
            return
        }
        delivery.send(reading, completion: completion)
    }

    private func transmit(_ reading: GarminGlucoseReading, to target: GarminDestination,
                          completion: @escaping GarminDeliveryQueue.Completion) {
        guard let selectedDevice else {
            finish(.failure(.noDeviceSelected), target: target, completion: completion)
            return
        }
        guard let device = knownDevices[selectedDevice.id],
              let app = (target == .bridge ? watchApps : dataFieldApps)[selectedDevice.id] else {
            finish(.failure(.appNotInstalled), target: target, completion: completion)
            return
        }
        guard ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected else {
            finish(.failure(.deviceNotConnected), target: target, completion: completion)
            return
        }

        let generation = selectionGeneration
        ConnectIQ.sharedInstance().sendMessage(
            GarminMessage(reading: reading).encoded(),
            to: app,
            progress: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == generation else {
                    completion(.failure(.deviceNotConnected))
                    return
                }
                self.finish(result == .success ? .success(()) : .failure(.sendFailed(Self.describe(result))),
                            target: target, completion: completion)
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
            if let fieldUUID = ConnectIQAppID.uuid(from: Self.dataFieldAppID) {
                dataFieldApps[id] = IQApp(uuid: fieldUUID, store: nil, device: device)
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

    private func finish(_ result: Result<Void, GarminTransportError>, target: GarminDestination,
                        completion: GarminDeliveryQueue.Completion) {
        if target == .bridge {
            switch result {
            case .success:
                lastSentAt = Date()
                lastError = nil
            case .failure(let error):
                lastError = error
                trace("Garmin: %{public}@", log: log, category: "Garmin", type: .error, error.userFacingDescription)
            }
        } else if case .failure(let error) = result {
            // The field is optional and may not be installed or running. Its
            // delivery result must not replace the existing Bridge status.
            trace("Mmolio DataField: %{public}@", log: log, category: "Garmin", type: .debug, error.userFacingDescription)
        }
        completion(result)
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

final class ConnectIQTransport: UnavailableGarminTransport {
    static let returnURLScheme = "xdrip-garmin"
}

#endif

extension Notification.Name {
    static let garminWatchStateDidChange = Notification.Name("garminWatchStateDidChange")
}
