import Foundation
import Combine

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
    @Published private(set) var state: CalibrationState = .idle
    @Published private(set) var lastResult: CalibrationResult?
    @Published private(set) var recentResults: [CalibrationResult] = []

    private var cancellable: AnyCancellable?
    private var samples: [BatteryReading] = []
    private let endThresholdPercent: Int = 5
    private var storeURL: URL = {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("BatMon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calibration.json")
    }()

    func bind(to publisher: PassthroughSubject<BatterySnapshot, Never>) {
        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.handle(snapshot: snap)
            }
        load()
    }

    func unbind() {
        cancellable?.cancel()
        cancellable = nil
        save()
    }

    func start() {
        state = .waitingFull
        samples.removeAll()
        save()
    }

    func stop() {
        state = .idle
        samples.removeAll()
        save()
    }

    private func handle(snapshot: BatterySnapshot) {
        switch state {
        case .idle:
            break

        case .waitingFull:
            // Нужно зарядить до 100% и отключить питание
            if snapshot.percentage >= 99 && !snapshot.isCharging && snapshot.powerSource == .battery {
                state = .running(start: Date(), atPercent: snapshot.percentage)
                samples.removeAll()
            }

        case .running(let start, let startPercent):
            // Если подключено питание — пауза
            if snapshot.isCharging || snapshot.powerSource == .ac {
                state = .paused
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
                let analysis = analytics.analyze(history: samples, snapshot: snapshot)
                if let url = ReportGenerator.generateHTML(result: analysis,
                                                          snapshot: snapshot,
                                                          history: samples,
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
            }

        case .completed:
            break
        }
    }

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
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // ignore
        }
    }

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
    }

    private func encode<T: Codable>(_ value: T) -> [String: Any] {
        let data = try! JSONEncoder().encode(value)
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return obj
    }

    private func decode<T: Codable>(_ obj: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
