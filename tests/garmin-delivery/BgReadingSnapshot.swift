import Foundation

// Minimal input fixture for compiling the actual GarminModels.swift in isolation.
struct BgReadingSnapshot {
    let finalValue: Double
    let timeStamp: Date
    let ordinal: Int
    func slopeOrdinal() -> Int { ordinal }
}
