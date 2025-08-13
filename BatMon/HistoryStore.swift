import Foundation
import Combine

struct BatteryReading: Codable, Equatable {
    var timestamp: Date
    var percentage: Int
    var isCharging: Bool
    var voltage: Double
    var temperature: Double
    var maxCapacity: Int?
    var designCapacity: Int?
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [BatteryReading] = []

    private let url: URL = {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("BatMon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    func start() { load() }
    func stop() { save() }

    func append(from snapshot: BatterySnapshot) {
        let r = BatteryReading(timestamp: Date(),
                               percentage: snapshot.percentage,
                               isCharging: snapshot.isCharging,
                               voltage: snapshot.voltage,
                               temperature: snapshot.temperature,
                               maxCapacity: snapshot.maxCapacity > 0 ? snapshot.maxCapacity : nil,
                               designCapacity: snapshot.designCapacity > 0 ? snapshot.designCapacity : nil)
        items.append(r)
        trimIfNeeded()
        save()
    }

    func recent(hours: Int) -> [BatteryReading] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return items.filter { $0.timestamp >= cutoff }
    }

    func recent(days: Int) -> [BatteryReading] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return items.filter { $0.timestamp >= cutoff }
    }

    /// Downsample to at most maxPoints by averaging buckets over time.
    func downsample(_ data: [BatteryReading], maxPoints: Int) -> [BatteryReading] {
        guard data.count > maxPoints, maxPoints > 0 else { return data }
        let total = data.count
        let bucketSize = max(1, total / maxPoints)
        var out: [BatteryReading] = []
        var i = 0
        while i < total {
            let j = min(total, i + bucketSize)
            let slice = data[i..<j]
            let avgP = slice.map(\.percentage).reduce(0, +) / max(1, slice.count)
            let avgV = slice.map(\.voltage).reduce(0.0, +) / Double(max(1, slice.count))
            let avgT = slice.map(\.temperature).reduce(0.0, +) / Double(max(1, slice.count))
            let ts = slice[slice.startIndex].timestamp
            let ch = slice.contains(where: { $0.isCharging })
            out.append(BatteryReading(timestamp: ts, percentage: avgP, isCharging: ch, voltage: avgV, temperature: avgT, maxCapacity: nil, designCapacity: nil))
            i = j
        }
        return out
    }

    private func trimIfNeeded() {
        // Compact old data: keep full resolution for 7 days, then 5‑мин бакеты до 30 дней, остальное выбрасываем.
        let now = Date()
        let day7 = now.addingTimeInterval(-7*86400)
        let day30 = now.addingTimeInterval(-30*86400)

        var fresh: [BatteryReading] = []
        var mid: [BatteryReading] = []
        for r in items {
            if r.timestamp >= day7 {
                fresh.append(r)
            } else if r.timestamp >= day30 {
                mid.append(r)
            }
        }

        // Compact mid to 5‑minute buckets
        let bucket: TimeInterval = 300
        var bucketed: [BatteryReading] = []
        var idx = 0
        let sortedMid = mid.sorted(by: { $0.timestamp < $1.timestamp })
        while idx < sortedMid.count {
            let start = sortedMid[idx].timestamp
            let end = start.addingTimeInterval(bucket)
            var block: [BatteryReading] = []
            while idx < sortedMid.count && sortedMid[idx].timestamp < end {
                block.append(sortedMid[idx])
                idx += 1
            }
            if !block.isEmpty {
                let avgP = block.map(\.percentage).reduce(0, +) / block.count
                let avgV = block.map(\.voltage).reduce(0.0, +) / Double(block.count)
                let avgT = block.map(\.temperature).reduce(0.0, +) / Double(block.count)
                let ch = block.contains(where: { $0.isCharging })
                bucketed.append(BatteryReading(timestamp: start, percentage: avgP, isCharging: ch, voltage: avgV, temperature: avgT, maxCapacity: nil, designCapacity: nil))
            }
        }

        self.items = (fresh + bucketed).sorted(by: { $0.timestamp < $1.timestamp })
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            // ignore
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([BatteryReading].self, from: data) {
            items = arr
        }
    }
}
