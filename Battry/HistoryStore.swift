import Foundation
import Combine

/// Одна запись истории измерений батареи
struct BatteryReading: Codable, Equatable {
    var timestamp: Date
    var percentage: Int
    var isCharging: Bool
    var voltage: Double
    var temperature: Double
    var maxCapacity: Int?
    var designCapacity: Int?
}

/// Событие для отображения маркеров на графиках
struct HistoryEvent: Codable, Equatable {
    var timestamp: Date
    var type: EventType
    var details: String?
    
    enum EventType: String, Codable {
        case generatorStarted = "generator_started"
        case generatorStopped = "generator_stopped"
        case videoStarted = "video_started"
        case videoStopped = "video_stopped"
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    /// Все записи истории (в памяти)
    @Published private(set) var items: [BatteryReading] = []
    /// События для маркеров на графиках (в памяти, не сохраняется)
    @Published private(set) var events: [HistoryEvent] = []
    /// Время завершения последнего теста калибровки
    @Published private(set) var lastTestCompletedAt: Date? = nil

    /// Путь к файлу истории в Application Support
    private let url: URL = {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let newDir = base.appendingPathComponent("Battry", isDirectory: true)
        let oldDir = base.appendingPathComponent("BatMon", isDirectory: true)
        // Migrate old data if present
        if fm.fileExists(atPath: oldDir.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            let oldFile = oldDir.appendingPathComponent("history.json")
            let newFile = newDir.appendingPathComponent("history.json")
            if fm.fileExists(atPath: oldFile.path) && !fm.fileExists(atPath: newFile.path) {
                try? fm.moveItem(at: oldFile, to: newFile)
            }
            // Try to remove old directory if empty (best-effort)
            if let contents = try? fm.contentsOfDirectory(atPath: oldDir.path), contents.isEmpty {
                try? fm.removeItem(at: oldDir)
            }
        }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        return newDir.appendingPathComponent("history.json")
    }()

    /// Размер файла истории на диске (байт)
    var fileSizeBytes: Int64 {
        let fm = FileManager.default
        do {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber { return size.int64Value }
        } catch {
            // ignore
        }
        return 0
    }

    /// Инициализация/остановка хранения
    func start() { load() }
    func stop() { save() }

    /// Добавляет снимок в историю и триггерит сохранение/усечение
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
    
    /// Добавляет событие для отображения маркера на графике
    func addEvent(_ type: HistoryEvent.EventType, details: String? = nil) {
        let event = HistoryEvent(timestamp: Date(), type: type, details: details)
        events.append(event)
        
        // Очищаем старые события (старше 30 дней)
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        events.removeAll { $0.timestamp < cutoff }
    }
    
    /// Возвращает события за указанный интервал времени [from; to]
    func eventsBetween(from: Date, to: Date) -> [HistoryEvent] {
        let start = min(from, to)
        let end = max(from, to)
        return events.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Полная очистка истории и удаление файла
    func clearAll() {
        items.removeAll()
        events.removeAll()
        let fm = FileManager.default
        try? fm.removeItem(at: url)
    }

    /// Последние N часов
    func recent(hours: Int) -> [BatteryReading] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return items.filter { $0.timestamp >= cutoff }
    }

    /// Последние N дней
    func recent(days: Int) -> [BatteryReading] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return items.filter { $0.timestamp >= cutoff }
    }

    /// Записи за указанный интервал времени [from; to]
    func between(from: Date, to: Date) -> [BatteryReading] {
        let start = min(from, to)
        let end = max(from, to)
        return items.filter { $0.timestamp >= start && $0.timestamp <= end }
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
        // Сжимаем старые данные: 7 дней — полная детализация; 7–30 дней — бакеты по 5 минут; старше — удаляем
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

        // Бакетируем середину по 5 минут с усреднением
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
    
    /// Устанавливает время завершения последнего теста калибровки
    func setLastTestCompletedAt(_ date: Date) {
        lastTestCompletedAt = date
    }
    
    /// Возвращает количество секунд с момента завершения последнего теста
    /// Возвращает nil, если тест не проводился
    func getTimeSinceLastTest() -> TimeInterval? {
        guard let lastTest = lastTestCompletedAt else { return nil }
        return Date().timeIntervalSince(lastTest)
    }
    
    /// Проверяет, прошел ли час с момента завершения последнего теста
    func isMoreThanHourSinceLastTest() -> Bool {
        guard let timeSince = getTimeSinceLastTest() else { return true }
        return timeSince > 3600 // 1 час в секундах
    }
}
