import Foundation

struct GarminDevice: Equatable, Identifiable, Codable {
    let id: UInt64
    let name: String
    var isConnected: Bool
}

enum GarminTransportError: Error, Equatable {
    case sdkUnavailable
    case noDeviceSelected
    case deviceNotConnected
    case appNotInstalled
    case sendFailed(String)

    var userFacingDescription: String {
        switch self {
        case .sdkUnavailable:
            return "Connect IQ SDK is not available in this build."
        case .noDeviceSelected:
            return "No Garmin watch is selected."
        case .deviceNotConnected:
            return "The Garmin watch is not connected."
        case .appNotInstalled:
            return "The xDrip Garmin receiver is not available on the watch."
        case .sendFailed(let detail):
            return "Send failed: \(detail)"
        }
    }
}

/// Small, source-independent snapshot sent to Garmin.
///
/// xDrip keeps mg/dL as the canonical internal unit. Garmin converts for display.
struct GarminGlucoseReading: Equatable {
    let mgDl: Double
    let trend: Int
    let measuredAt: Date
    let sequence: Int

    init(snapshot: BgReadingSnapshot) {
        mgDl = snapshot.finalValue

        // xDrip slope ordinals run in the opposite direction to the compact protocol
        // already used by the Garmin receiver:
        // xDrip 1...7 = rising quickly ... falling quickly
        // Garmin 1...7 = falling quickly ... rising quickly
        let xDripOrdinal = snapshot.slopeOrdinal()
        trend = (1...7).contains(xDripOrdinal) ? 8 - xDripOrdinal : 0

        measuredAt = snapshot.timeStamp
        sequence = Int(snapshot.timeStamp.timeIntervalSince1970)
    }
}

struct GarminMessage: Equatable {
    static let currentVersion = 1
    static let xDripSource = 3

    enum Key {
        static let version = "v"
        static let mgDl = "g"
        static let trend = "t"
        static let measuredAt = "m"
        static let source = "s"
        static let sequence = "q"
    }

    let reading: GarminGlucoseReading

    func encoded() -> [String: Any] {
        [
            Key.version: Self.currentVersion,
            Key.mgDl: Int(reading.mgDl.rounded()),
            Key.trend: reading.trend,
            Key.measuredAt: Int(reading.measuredAt.timeIntervalSince1970),
            Key.source: Self.xDripSource,
            Key.sequence: reading.sequence
        ]
    }
}

struct GarminSendPolicy {
    private var lastSequence: Int?
    private var lastMeasuredAt: Date?

    enum Decision {
        case send
        case skipDuplicate
        case skipOlder
    }

    mutating func decide(_ reading: GarminGlucoseReading) -> Decision {
        if let lastSequence {
            if reading.sequence == lastSequence { return .skipDuplicate }
            if reading.sequence < lastSequence { return .skipOlder }
        }

        if let lastMeasuredAt, reading.measuredAt < lastMeasuredAt {
            return .skipOlder
        }

        lastSequence = reading.sequence
        lastMeasuredAt = reading.measuredAt
        return .send
    }

    mutating func reset() {
        lastSequence = nil
        lastMeasuredAt = nil
    }
}

enum ConnectIQAppID {
    static func hyphenated(_ identifier: String) -> String? {
        let hex = identifier.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        let characters = Array(hex)
        let groups = [0 ..< 8, 8 ..< 12, 12 ..< 16, 16 ..< 20, 20 ..< 32]
        return groups.map { String(characters[$0]) }.joined(separator: "-")
    }

    static func uuid(from identifier: String) -> UUID? {
        hyphenated(identifier).flatMap(UUID.init(uuidString:))
    }
}

enum GarminDestination: Hashable {
    case bridge
    case dataField
}

/// Serialize the two deliveries so they cannot compete for the watch connection.
/// Each destination has its own duplicate policy: a missing data field must not
/// prevent Bridge delivery, and a failed Bridge must not prevent activity data.
final class GarminDeliveryQueue {
    typealias Completion = (Result<Void, GarminTransportError>) -> Void
    typealias Sender = (GarminDestination, GarminGlucoseReading, @escaping Completion) -> Void

    private struct Request {
        let reading: GarminGlucoseReading
        let generation: Int
        let completion: Completion
    }

    private let sender: Sender
    private var policies: [GarminDestination: GarminSendPolicy] = [:]
    private var pending: [Request] = []
    private var running = false
    private var generation = 0

    init(sender: @escaping Sender) { self.sender = sender }

    /// Invalidate queued work and callbacks after selecting another watch or stopping.
    func reset() {
        generation += 1
        policies.removeAll()
    }

    func send(_ reading: GarminGlucoseReading, completion: @escaping Completion) {
        pending.append(Request(reading: reading, generation: generation, completion: completion))
        processNext()
    }

    private func processNext() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let request = pending.removeFirst()
        deliver(.bridge, request: request) { [self] bridgeResult in
            // Attempt the optional destination even if Bridge failed. Keeping the
            // completion until both callbacks also keeps GarminBackgroundWork alive.
            deliver(.dataField, request: request) { [self] _ in
                let result: Result<Void, GarminTransportError> = request.generation == generation
                    ? bridgeResult : .failure(.deviceNotConnected)
                request.completion(result)
                running = false
                processNext()
            }
        }
    }

    private func deliver(_ target: GarminDestination, request: Request, completion: @escaping Completion) {
        guard request.generation == generation else {
            completion(.failure(.deviceNotConnected))
            return
        }
        var policy = policies[target] ?? GarminSendPolicy()
        switch policy.decide(request.reading) {
        case .skipDuplicate, .skipOlder:
            completion(.success(()))
            return
        case .send:
            policies[target] = policy
        }
        sender(target, request.reading) { [self] result in
            if request.generation == generation, case .failure = result {
                policies[target] = GarminSendPolicy()
            }
            completion(result)
        }
    }
}
