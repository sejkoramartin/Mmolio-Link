import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func success(_ result: Result<Void, GarminTransportError>) -> Bool {
    if case .success = result { return true }
    return false
}
func reading(_ seconds: Int) -> GarminGlucoseReading {
    GarminGlucoseReading(snapshot: BgReadingSnapshot(finalValue: 115,
        timeStamp: Date(timeIntervalSince1970: Double(seconds)), ordinal: 3))
}

final class Harness {
    var attempts: [(GarminDestination, GarminGlucoseReading)] = []
    var callbacks: [GarminDeliveryQueue.Completion] = []
    var results: [Result<Void, GarminTransportError>] = []
    lazy var queue = GarminDeliveryQueue { [unowned self] target, value, done in
        check(callbacks.isEmpty, "SDK sends must not overlap")
        attempts.append((target, value))
        callbacks.append(done)
    }
    func send(_ value: GarminGlucoseReading) {
        queue.send(value) { [unowned self] in results.append($0) }
    }
    func ack(_ result: Result<Void, GarminTransportError> = .success(())) {
        check(callbacks.count == 1, "Exactly one SDK request must be outstanding")
        let callback = callbacks.removeFirst()
        callback(result)
    }
}

let sample = reading(1_790_020_000)
let packet = GarminMessage(reading: sample).encoded()
check(Set(packet.keys) == Set(["v", "g", "t", "m", "s", "q"]), "Wire keys changed")
check(packet["v"] as? Int == 1 && packet["s"] as? Int == 3, "Wire version/source changed")
check(packet["g"] as? Int == 115 && packet["t"] as? Int == 5, "Glucose/trend mapping changed")
check(packet["m"] as? Int == 1_790_020_000 && packet["q"] as? Int == 1_790_020_000,
      "Measurement time/sequence must not be refreshed at delivery")

// A missing data field is optional; retry only its failed delivery on a repeat.
do {
    let h = Harness()
    h.send(sample)
    check(h.attempts.map { $0.0 } == [.bridge], "Bridge must be attempted first")
    h.ack()
    check(h.results.isEmpty, "Do not end iOS background work before DataField completes")
    h.ack(.failure(.appNotInstalled))
    check(success(h.results[0]), "Optional failure must not fail Bridge")
    h.send(sample)
    check(h.attempts.map { $0.0 } == [.bridge, .dataField, .dataField],
          "Retry optional failure without resending successful Bridge")
    h.ack()
    h.send(sample)
    check(h.attempts.count == 3 && h.results.count == 3, "Deduplicate both successful destinations")
    check(h.attempts.allSatisfy { $0.1 == sample }, "Both targets must receive identical snapshots")
}

// The field still gets data when Bridge fails, and Bridge's error is not hidden.
do {
    let h = Harness()
    h.send(sample)
    h.ack(.failure(.sendFailed("Bridge unavailable")))
    check(h.attempts.map { $0.0 } == [.bridge, .dataField], "Bridge failure cannot block field")
    h.ack()
    check(!success(h.results[0]), "Keep primary failure visible")
    h.send(sample)
    check(h.attempts.count == 3 && h.attempts.last!.0 == .bridge, "Retry only failed Bridge")
    h.ack()
    check(h.results.count == 2 && success(h.results[1]), "Successful field must not need resending")
}

// Two overlapping requests are serialized, and older data stays suppressed.
do {
    let h = Harness()
    h.send(sample)
    h.send(reading(1_790_020_300))
    check(h.attempts.count == 1, "Second snapshot must wait")
    h.ack(); h.ack(); h.ack(); h.ack()
    check(h.attempts.map { $0.0 } == [.bridge, .dataField, .bridge, .dataField], "Unexpected order")
    h.send(sample)
    check(h.attempts.count == 4 && h.results.count == 3, "Do not send older data to either target")
}

// Changing watches invalidates outstanding/queued work and its duplicate history.
do {
    let h = Harness()
    h.send(sample)
    h.send(reading(1_790_020_300))
    h.queue.reset()
    h.send(sample)
    h.ack()
    check(h.results.count == 2 && h.results.allSatisfy { !success($0) }, "Cancel work for old watch")
    check(h.attempts.map { $0.0 } == [.bridge, .bridge], "No old data field send after reset")
    h.ack(); h.ack()
    check(success(h.results.last!), "Same measurement must reach new watch")
}

// Early connection failures must not mark data delivered or suppress a reconnect retry.
do {
    let h = Harness()
    h.send(sample)
    h.ack(.failure(.deviceNotConnected)); h.ack(.failure(.deviceNotConnected))
    h.send(sample)
    h.ack(); h.ack()
    check(h.attempts.count == 4 && success(h.results.last!), "Reconnect must retry both targets")
}

print("PASS: original wire format; optional failure isolation; Bridge failure isolation; independent retries; duplicate/older suppression; serialized delivery; background completion; selection reset; reconnect")
