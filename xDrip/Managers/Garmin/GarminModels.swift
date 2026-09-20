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
