import Foundation
import Combine

/// Итог одного сеанса калибровки/теста
struct CalibrationResult: Codable, Equatable {
    var startedAt: Date
    var finishedAt: Date
    var startPercent: Int
    var endPercent: Int
    var durationHours: Double
    var avgDischargePerHour: Double
    var estimatedRuntimeFrom100To0Hours: Double
    var reportPath: String? = nil
}

/// Состояние процесса калибровки
enum CalibrationState: Equatable {
    case idle
    case waitingFull // ждём 100% и отключение от сети
    case running(start: Date, atPercent: Int)
    case paused // подключили питание
    case completed(result: CalibrationResult)

    var isActive: Bool {
        if case .running = self { return true }
        if case .waitingFull = self { return true }
        if case .paused = self { return true }
        return false
    }
}

@MainActor
final class CalibrationEngine: ObservableObject {
    /// Текущее состояние сеанса
    @Published private(set) var state: CalibrationState = .idle
    /// Последний завершённый результат
    @Published private(set) var lastResult: CalibrationResult?
    /// Последние N результатов (для истории)
    @Published private(set) var recentResults: [CalibrationResult] = []
    /// Флаг: был авто‑сброс из‑за слишком большого разрыва в данных
    @Published var autoResetDueToGap: Bool = false

    private var cancellable: AnyCancellable?
    private var samples: [BatteryReading] = []
    /// Порог завершения теста по проценту (до 5%)
    private let endThresholdPercent: Int = 5
    /// Максимально допустимый разрыв между сэмплами, чтобы продолжить (сек)
    private var maxResumeGap: TimeInterval = 1800 // по умолчанию 30 минут
    private var lastSampleAt: Date?
    private var justBound = false
    /// Необязательное подключение к хранилищу истории для восстановления сессии
    private weak var historyStore: HistoryStore?
    /// Путь к файлу с состоянием/результатами
    private var storeURL: URL = {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let newDir = base.appendingPathComponent("Battry", isDirectory: true)
        let oldDir = base.appendingPathComponent("BatMon", isDirectory: true)
        // Migrate old data if present
        if fm.fileExists(atPath: oldDir.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            let oldFile = oldDir.appendingPathComponent("calibration.json")
            let newFile = newDir.appendingPathComponent("calibration.json")
            if fm.fileExists(atPath: oldFile.path) && !fm.fileExists(atPath: newFile.path) {
                try? fm.moveItem(at: oldFile, to: newFile)
            }
            // Try to remove old directory if empty (best-effort)
            if let contents = try? fm.contentsOfDirectory(atPath: oldDir.path), contents.isEmpty {
                try? fm.removeItem(at: oldDir)
            }
        }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        return newDir.appendingPathComponent("calibration.json")
    }()

    /// Подписывается на поток снимков батареи
    func bind(to publisher: PassthroughSubject<BatterySnapshot, Never>) {
        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.handle(snapshot: snap)
            }
        load()
        justBound = true
    }

     /// Подключает хранилище истории для использования данных между рестартами
     func attachHistory(_ store: HistoryStore) {
         self.historyStore = store
     }

    /// Отвязывает подписку и сохраняет прогресс
    func unbind() {
        cancellable?.cancel()
        cancellable = nil
        save()
    }

    /// Начинает новую сессию (переход в ожидание 100%)
    func start() {
        state = .waitingFull
        samples.removeAll()
        lastSampleAt = nil
        autoResetDueToGap = false
        save()
    }

    /// Останавливает и сбрасывает текущую сессию
    func stop() {
        state = .idle
        samples.removeAll()
        lastSampleAt = nil
        autoResetDueToGap = false
        save()
    }

    /// Настраивает допустимый разрыв между сэмплами при возобновлении (сек)
    func setMaxResumeGap(_ seconds: TimeInterval) {
        maxResumeGap = max(0, seconds)
        save()
    }

    /// Скрывает уведомление об авто‑сбросе
    func acknowledgeAutoResetNotice() {
        autoResetDueToGap = false
    }

    /// Основная обработка каждого снимка батареи в зависимости от состояния
    private func handle(snapshot: BatterySnapshot) {
        // При запуске приложения проверяем, можно ли корректно продолжить сессию
        if justBound {
            justBound = false
            if case .running = state {
                let now = Date()
                let hasLast = (lastSampleAt != nil)
                let gap = hasLast ? now.timeIntervalSince(lastSampleAt!) : .greatestFiniteMagnitude
                let gapIsAcceptable = hasLast && gap <= maxResumeGap
                if !gapIsAcceptable {
                    // Разрешаем продолжить, если всё ещё на батарее, нет зарядки
                    // и процент не вырос по сравнению с последним сэмплом
                    let stillOnBattery = (snapshot.powerSource == .battery) && !snapshot.isCharging
                    let lastPct = samples.last?.percentage ?? snapshot.percentage
                    let noIncrease = snapshot.percentage <= lastPct
                    if !(stillOnBattery && noIncrease) {
                        state = .waitingFull
                        samples.removeAll()
                        autoResetDueToGap = true
                        save()
                        return
                    }
                }
            }
        }
        switch state {
        case .idle:
            break

        case .waitingFull:
            // Нужно зарядить до 100% и отключить питание
            if snapshot.percentage >= 99 && !snapshot.isCharging && snapshot.powerSource == .battery {
                state = .running(start: Date(), atPercent: snapshot.percentage)
                samples.removeAll()
                lastSampleAt = Date()
                save()
            }

        case .running(let start, let startPercent):
            // Если подключено питание — пауза
            if snapshot.isCharging || snapshot.powerSource == .ac {
                state = .paused
                save()
                return
            }
            // Сохраняем сэмпл
            let reading = BatteryReading(timestamp: Date(),
                                         percentage: snapshot.percentage,
                                         isCharging: snapshot.isCharging,
                                         voltage: snapshot.voltage,
                                         temperature: snapshot.temperature,
                                         maxCapacity: snapshot.maxCapacity,
                                         designCapacity: snapshot.designCapacity)
            samples.append(reading)
            lastSampleAt = reading.timestamp
            save()

            // Добежали до порога — завершаем
            if snapshot.percentage <= endThresholdPercent {
                let end = Date()
                let dt = end.timeIntervalSince(start) / 3600.0
                let dPercent = Double(startPercent - snapshot.percentage)
                let dischargePerHour = dPercent / max(0.001, dt)
                let runtime = dischargePerHour > 0 ? 100.0 / dischargePerHour : 0.0

                var res = CalibrationResult(startedAt: start,
                                            finishedAt: end,
                                            startPercent: startPercent,
                                            endPercent: snapshot.percentage,
                                            durationHours: dt,
                                            avgDischargePerHour: dischargePerHour,
                                            estimatedRuntimeFrom100To0Hours: runtime)

                // Считаем аналитику и генерируем отчёт
                let analytics = AnalyticsEngine()
                let sessionHistory: [BatteryReading]
                if let hs = historyStore {
                    sessionHistory = hs.between(from: start, to: end)
                } else {
                    sessionHistory = samples
                }
                let analysis = analytics.analyze(history: sessionHistory, snapshot: snapshot)
                if let url = ReportGenerator.generateHTML(result: analysis,
                                                          snapshot: snapshot,
                                                          history: sessionHistory,
                                                          calibration: res) {
                    res.reportPath = url.path
                }

                state = .completed(result: res)
                lastResult = res
                recentResults.append(res)
                if recentResults.count > 5 {
                    recentResults = Array(recentResults.suffix(5))
                }
                save()
            }

        case .paused:
            // Если снова ушли с сети — продолжаем бежать, но перезапускаем калибровку (нужен непрерывный интервал)
            if !snapshot.isCharging && snapshot.powerSource == .battery && snapshot.percentage >= 99 {
                state = .running(start: Date(), atPercent: snapshot.percentage)
                samples.removeAll()
                lastSampleAt = Date()
                save()
            }

        case .completed:
            break
        }
    }

    /// Сохраняет прогресс/результаты в JSON
    private func save() {
        var obj: [String: Any] = [:]
        switch state {
        case .completed(let result):
            obj["state"] = "completed"
            obj["result"] = encode(result)
        case .idle:
            obj["state"] = "idle"
        case .running(let start, let p):
            obj["state"] = "running"
            obj["start"] = start.timeIntervalSince1970
            obj["p"] = p
        case .waitingFull:
            obj["state"] = "waitingFull"
        case .paused:
            obj["state"] = "paused"
        }
        if let lr = lastResult {
            obj["last"] = encode(lr)
        }
        if !recentResults.isEmpty {
            obj["recent"] = recentResults.map { encode($0) }
        }
        if !samples.isEmpty {
            obj["samples"] = samples.map { encode($0) }
        }
        if let ls = lastSampleAt {
            obj["lastSampleAt"] = ls.timeIntervalSince1970
        }
        obj["maxResumeGap"] = maxResumeGap
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // ignore
        }
    }

    /// Загружает сохранённое состояние/результаты из JSON
    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let lastDict = obj["last"] as? [String: Any],
           let lr: CalibrationResult = decode(lastDict) {
            lastResult = lr
        }
        if let recentArr = obj["recent"] as? [[String: Any]] {
            var decoded: [CalibrationResult] = []
            for d in recentArr {
                if let r: CalibrationResult = decode(d) {
                    decoded.append(r)
                }
            }
            if !decoded.isEmpty {
                recentResults = Array(decoded.suffix(5))
            }
        }
        if let stateStr = obj["state"] as? String {
            switch stateStr {
            case "completed":
                if let rd = obj["result"] as? [String: Any],
                   let res: CalibrationResult = decode(rd) {
                    state = .completed(result: res)
                }
            case "running":
                if let ts = obj["start"] as? TimeInterval,
                   let p = obj["p"] as? Int {
                    state = .running(start: Date(timeIntervalSince1970: ts), atPercent: p)
                }
            case "waitingFull":
                state = .waitingFull
            case "paused":
                state = .paused
            default:
                state = .idle
            }
        }
        if let ls = obj["lastSampleAt"] as? TimeInterval {
            lastSampleAt = Date(timeIntervalSince1970: ls)
        }
        if let arr = obj["samples"] as? [[String: Any]] {
            var decoded: [BatteryReading] = []
            for d in arr {
                if let r: BatteryReading = decode(d) {
                    decoded.append(r)
                }
            }
            samples = decoded
        }
        if let mg = obj["maxResumeGap"] as? TimeInterval {
            maxResumeGap = mg
        }
    }

    /// Кодирует Codable-структуру в словарь для JSON
    private func encode<T: Codable>(_ value: T) -> [String: Any] {
        let data = try! JSONEncoder().encode(value)
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return obj
    }

    /// Декодирует словарь JSON в Codable-структуру
    private func decode<T: Codable>(_ obj: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
