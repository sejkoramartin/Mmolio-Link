import UIKit

/// Extends the short BLE wake window long enough for Connect IQ to finish a send.
final class GarminBackgroundWork {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let name: String

    init(_ name: String) {
        self.name = name
    }

    func begin() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.begin() }
            return
        }

        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.end() }
            return
        }

        guard identifier != .invalid else { return }
        let finished = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(finished)
    }

    deinit {
        if identifier != .invalid {
            let finished = identifier
            identifier = .invalid
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(finished)
            }
        }
    }
}
