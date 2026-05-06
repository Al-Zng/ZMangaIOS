import Foundation

final class Logger: ObservableObject {
    static let shared = Logger()
    @Published var entries: [LogEntry] = []
    private let maxEntries = 500
    private let queue = DispatchQueue(label: "logger.queue", qos: .utility)

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let message: String
    }

    func log(_ message: String, category: String = "General") {
        queue.async { [weak self] in
            guard let self = self else { return }
            let entry = LogEntry(timestamp: Date(), category: category, message: message)
            DispatchQueue.main.async {
                self.entries.append(entry)
                if self.entries.count > self.maxEntries {
                    self.entries.removeFirst(self.entries.count - self.maxEntries)
                }
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}