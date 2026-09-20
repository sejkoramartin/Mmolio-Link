import Foundation
import OSLog

final class GarminManager {
    static let shared = GarminManager()

    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: "Garmin")
    private let transport: GarminTransport
    private var bgReadingsAccessor: BgReadingsAccessor?
    private var started = false

    private init(transport: GarminTransport = GarminTransportFactory.make()) {
        self.transport = transport
    }

    var devices: [GarminDevice] { transport.devices }
    var selectedDevice: GarminDevice? { transport.selectedDevice }
    var lastSentAt: Date? { transport.lastSentAt }
    var lastError: GarminTransportError? { transport.lastError }

    var statusText: String {
        guard GarminTransportFactory.isAvailable else { return "SDK Unavailable" }
        guard UserDefaults.standard.garminWatchEnabled else { return "Disabled" }
        guard let selectedDevice else { return "Not Configured" }
        return selectedDevice.isConnected ? "Connected" : "Disconnected"
    }

    var isConnected: Bool {
        UserDefaults.standard.garminWatchEnabled && selectedDevice?.isConnected == true
    }

    func configure(coreDataManager: CoreDataManager) {
        if bgReadingsAccessor == nil {
            bgReadingsAccessor = BgReadingsAccessor(coreDataManager: coreDataManager)
        }
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        transport.start()
        notifyStateChanged()
    }

    func stop() {
        guard started else { return }
        transport.stop()
        started = false
        notifyStateChanged()
    }

    func requestDevices() {
        start()
        transport.requestDevices()
    }

    func handleReturn(from url: URL) {
        start()
        transport.handleReturn(from: url)
        notifyStateChanged()
    }

    func select(_ device: GarminDevice?) {
        transport.select(device)
        notifyStateChanged()
    }

    /// Sends the newest visible, post-processed xDrip value.
    ///
    /// Backfill batches may contain several historical readings; fetching from Core Data here
    /// guarantees Garmin receives the same latest value xDrip currently shows.
    func sendLatestReading(force: Bool = false) {
        guard force || UserDefaults.standard.garminWatchEnabled else { return }
        guard let bgReadingsAccessor,
              let snapshot = bgReadingsAccessor.lastSnapshot(forSensor: nil) else {
            return
        }

        let reading = GarminGlucoseReading(snapshot: snapshot)
        let backgroundWork = GarminBackgroundWork("Send glucose to Garmin")
        backgroundWork.begin()

        transport.send(reading) { [weak self, backgroundWork] result in
            defer { backgroundWork.end() }

            guard let self else { return }
            switch result {
            case .success:
                trace(
                    "Garmin glucose sent: %{public}@ mg/dL",
                    log: self.log,
                    category: "Garmin",
                    type: .debug,
                    Int(reading.mgDl.rounded()).description
                )
            case .failure(let error):
                trace(
                    "Garmin glucose send failed: %{public}@",
                    log: self.log,
                    category: "Garmin",
                    type: .error,
                    error.userFacingDescription
                )
            }

            self.notifyStateChanged()
        }
    }

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .garminWatchStateDidChange, object: nil)
        }
    }
}
