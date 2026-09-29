import Foundation
import Network
import Combine

final class ArchiveNetworkMonitor: ObservableObject {
    static let shared = ArchiveNetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.storagebuild.networkmonitor")

    @Published private(set) var isOnline: Bool = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isOnline = satisfied
            }
        }
        monitor.start(queue: queue)
    }

    func currentStatus() async -> Bool {
        for _ in 0..<10 {
            if isOnline { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isOnline
    }
}
