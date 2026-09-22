import Foundation

// Compile the production G7 packet decoder without the iOS application.
enum DexcomAlgorithmState: UInt8 {
    case None = 0
    case okay = 6
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

for (raw, expected) in [(UInt8(0), 4), (9, 4), (10, 3), (20, 2), (30, 2),
                        (31, 1), (UInt8(bitPattern: -10), 5),
                        (UInt8(bitPattern: -20), 6), (UInt8(bitPattern: -31), 7),
                        (0x7F, 0)] {
    check(G7SensorTrend.ordinal(rawByte: raw) == expected, "wrong trend band for \(raw)")
}
check(G7SensorTrend.arrow(ordinal: 7) == "↓↓", "wrong downward arrow")
check(G7SensorTrend.name(ordinal: 0) == "NOT COMPUTABLE", "missing trend must stay unknown")

var direct = Data(repeating: 0, count: 19)
direct[0] = 0x4E
direct[12] = 120
direct[14] = 6
direct[15] = UInt8(bitPattern: -32)
check(G7GlucoseMessage(data: direct)?.sensorTrendOrdinal == 7, "direct packet lost trend")
direct[15] = 0x7F
check(G7GlucoseMessage(data: direct)?.sensorTrendOrdinal == 0, "direct no-trend sentinel lost")
check(G7GlucoseMessage(data: direct.prefix(18)) == nil, "short direct packet accepted")

var coexistence = Data(repeating: 0, count: 16)
coexistence[0] = 0x31
coexistence[10] = 120
coexistence[12] = 6
coexistence[13] = UInt8(bitPattern: -32)
check(G7CoexistenceGlucoseMessage(data: coexistence)?.sensorTrendOrdinal == 7,
      "coexistence packet lost trend")
coexistence[13] = 0x7F
check(G7CoexistenceGlucoseMessage(data: coexistence)?.sensorTrendOrdinal == 0,
      "coexistence no-trend sentinel lost")
check(G7CoexistenceGlucoseMessage(data: coexistence.prefix(15)) == nil,
      "short coexistence packet accepted")

print("G7 sensor trend parser: passed")
