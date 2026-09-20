import Foundation

protocol GarminTransport: AnyObject {
    var devices: [GarminDevice] { get }
    var selectedDevice: GarminDevice? { get }
    var lastSentAt: Date? { get }
    var lastError: GarminTransportError? { get }

    func start()
    func stop()
    func requestDevices()
    func handleReturn(from url: URL)
    func select(_ device: GarminDevice?)
    func send(_ reading: GarminGlucoseReading, completion: @escaping (Result<Void, GarminTransportError>) -> Void)
}

final class UnavailableGarminTransport: GarminTransport {
    private(set) var devices: [GarminDevice] = []
    private(set) var selectedDevice: GarminDevice?
    private(set) var lastSentAt: Date?
    private(set) var lastError: GarminTransportError? = .sdkUnavailable

    func start() {}
    func stop() {}
    func requestDevices() {}
    func handleReturn(from url: URL) {}
    func select(_ device: GarminDevice?) { selectedDevice = device }

    func send(_ reading: GarminGlucoseReading,
              completion: @escaping (Result<Void, GarminTransportError>) -> Void) {
        lastError = .sdkUnavailable
        completion(.failure(.sdkUnavailable))
    }
}

enum GarminTransportFactory {
    static func make() -> GarminTransport {
        #if canImport(ConnectIQ)
        return ConnectIQTransport()
        #else
        return UnavailableGarminTransport()
        #endif
    }

    static var isAvailable: Bool {
        #if canImport(ConnectIQ)
        return true
        #else
        return false
        #endif
    }
}
