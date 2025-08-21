import Foundation
import Combine

enum FileError: Error, LocalizedError {
    case fileNotFound
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .parseError:
            return "Failed to parse file"
        }
    }
}

/// Настройки генератора нагрузки для сессии калибровки
struct LoadGeneratorSessionSettings {
    var isEnabled: Bool = false
    var profile: LoadProfile = .medium
    var autoStart: Bool = false
}

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
    var dataPath: String? = nil
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
    
    // MARK: - Load Generator Integration
    
    /// Ссылки на генераторы нагрузки
    private weak var loadGenerator: LoadGenerator?
    // Video load removed
    
    /// Настройки генератора для текущей сессии
    @Published var loadGeneratorSettings = LoadGeneratorSessionSettings()
    
    /// Метаданные генератора для текущей сессии
    @Published private(set) var currentLoadMetadata = ReportGenerator.LoadGeneratorMetadata()

    private var cancellable: AnyCancellable?
    private var samples: [BatteryReading] = []
    private weak var batteryViewModel: BatteryViewModel?
    private weak var quickHealthTest: QuickHealthTest?
    private let alertManager = AlertManager.shared
    /// Порог завершения теста по проценту (до 5%)
    private let endThresholdPercent: Int = 5
    /// Максимально допустимый разрыв между сэмплами, чтобы продолжить (сек)
    private var maxResumeGap: TimeInterval = 1800 // по умолчанию 30 минут
    private var lastSampleAt: Date?
    private var justBound = false
    /// Необязательное подключение к хранилищу истории для восстановления сессии
    private weak var historyStore: HistoryStore?
    /// Токен активности, предотвращающий сон системы
    private var activity: NSObjectProtocol?
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

    // MARK: - CP Discharge Mode
    // Always use CP (Constant Power) mode for all tests
    private lazy var constantPowerController = ConstantPowerController()
    private var cpTargetPowerW: Double = 0
    private var cpPreset: PowerPreset = .medium

    /// Подписывается на поток снимков батареи
    func bind(to publisher: PassthroughSubject<BatterySnapshot, Never>, viewModel: BatteryViewModel? = nil) {
        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.handle(snapshot: snap)
            }
        self.batteryViewModel = viewModel
        load()
        justBound = true
        updatePollingMode()
    }

     /// Подключает хранилище истории для использования данных между рестартами
     func attachHistory(_ store: HistoryStore) {
         self.historyStore = store
     }
     
     /// Привязывает генераторы нагрузки для автоматического управления
     func attachLoadGenerators(cpu: LoadGenerator) {
         self.loadGenerator = cpu
     }
     
     /// Привязывает QuickHealthTest для проверки взаимоисключающих состояний
     func attachQuickHealthTest(_ quickHealthTest: QuickHealthTest) {
         self.quickHealthTest = quickHealthTest
     }

    /// Отвязывает подписку и сохраняет прогресс
    func unbind() {
        cancellable?.cancel()
        cancellable = nil
        save()
    }


    /// Запускает полный тест батареи с CP-разрядом до 5% с выбранным пресетом (0.1/0.2/0.3C)
    func start(preset: PowerPreset) {
        // Проверяем, что не запущен быстрый тест
        if let quickTest = quickHealthTest, quickTest.state.isActive {
            // Используем alertManager для показа ошибки
            alertManager.showError(
                title: "Cannot Start Test",
                message: "Cannot start full battery test: quick health test is running"
            )
            return
        }
        
        cpPreset = preset
        state = .waitingFull
        samples.removeAll()
        lastSampleAt = nil
        autoResetDueToGap = false
        // Обнуляем метаданные генератора
        currentLoadMetadata = ReportGenerator.LoadGeneratorMetadata()
        save()
        updateSleepPrevention()
        updatePollingMode()
    }

    /// Останавливает и сбрасывает текущую сессию
    func stop() {
        // Останавливаем генераторы
        stopLoadGenerators()
        
        state = .idle
        samples.removeAll()
        lastSampleAt = nil
        autoResetDueToGap = false
        save()
        updateSleepPrevention()
        updatePollingMode()
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
                        updatePollingMode()
                        return
                    }
                }
            }
        }
        switch state {
        case .idle:
            break

        case .waitingFull:
            // Нужно зарядить до 98%+ и отключить питание
            if snapshot.percentage >= 98 && !snapshot.isCharging && snapshot.powerSource == .battery {
                state = .running(start: Date(), atPercent: snapshot.percentage)
                samples.removeAll()
                lastSampleAt = Date()
                
                // Автозапуск генератора если включен
                if loadGeneratorSettings.isEnabled && loadGeneratorSettings.autoStart {
                    startLoadGenerators()
                }

                // Вычисляем целевую мощность для CP-режима и запускаем контроллер
                // Используем среднее V_OC из недавней истории, fallback на 11.1 В
                var avgVOC: Double = 11.1
                if let hs = historyStore {
                    let recent = hs.recent(hours: 6)
                    if let v = OCVAnalyzer.averageVOC(from: recent) {
                        avgVOC = max(5.0, v)
                    }
                }
                cpTargetPowerW = PowerCalculator.targetPower(
                    for: cpPreset,
                    designCapacityMah: snapshot.designCapacity,
                    nominalVoltage: avgVOC
                )
                setupCPController()
                constantPowerController.start(targetPower: cpTargetPowerW)
                
                save()
                updateSleepPrevention()
                updatePollingMode()
            }

        case .running(let start, let startPercent):
            // Если подключено питание — пауза
            if snapshot.isCharging || snapshot.powerSource == .ac {
                // Останавливаем генераторы при паузе
                stopLoadGenerators()
                
                state = .paused
                save()
                updateSleepPrevention()
                updatePollingMode()
                return
            }
            // Сохраняем сэмпл
            let reading = BatteryReading(timestamp: Date(),
                                         percentage: snapshot.percentage,
                                         isCharging: snapshot.isCharging,
                                         voltage: snapshot.voltage,
                                         temperature: snapshot.temperature,
                                         maxCapacity: snapshot.maxCapacity,
                                         designCapacity: snapshot.designCapacity,
                                         amperage: snapshot.amperage)
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

                // Останавливаем CP-контроллер
                constantPowerController.stop()

                // Считаем аналитику и генерируем отчёт
                let sessionHistory: [BatteryReading]
                if let hs = historyStore {
                    sessionHistory = hs.between(from: start, to: end)
                } else {
                    sessionHistory = samples
                }
                let analysis = AnalyticsEngine.performAnalysis(history: sessionHistory, snapshot: snapshot)
                if let htmlContent = ReportGenerator.generateHTMLContent(result: analysis,
                                                                         snapshot: snapshot,
                                                                         history: sessionHistory,
                                                                         calibration: res,
                                                                         loadGeneratorMetadata: currentLoadMetadata) {
                    // Сохраняем отчет во временную папку с именем на основе даты начала теста
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    let dateString = formatter.string(from: res.startedAt)
                    let filename = "Battry_Calibration_\(dateString).html"
                    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    let reportURL = tempDir.appendingPathComponent(filename)
                    
                    do {
                        try htmlContent.write(to: reportURL, atomically: true, encoding: .utf8)
                        res.reportPath = reportURL.path
                    } catch {
                        alertManager.showReportError(error)
                    }
                }

                // Останавливаем генераторы при завершении
                stopLoadGenerators()
                
                // Сохраняем полные данные теста
                if let dataPath = saveTestData(result: res, samples: samples, snapshot: snapshot) {
                    res.dataPath = dataPath
                }
                
                // Уведомляем HistoryStore о завершении теста для корректного отображения метрик
                historyStore?.setLastTestCompletedAt(end)
                
                state = .completed(result: res)
                lastResult = res
                recentResults.append(res)
                if recentResults.count > 5 {
                    recentResults = Array(recentResults.suffix(5))
                }
                save()
                updateSleepPrevention()
                updatePollingMode()
            }

        case .paused:
            // Если снова ушли с сети — продолжаем бежать, но перезапускаем калибровку (нужен непрерывный интервал)
            if !snapshot.isCharging && snapshot.powerSource == .battery && snapshot.percentage >= 98 {
                state = .running(start: Date(), atPercent: snapshot.percentage)
                samples.removeAll()
                lastSampleAt = Date()
                
                // Перезапускаем генератор если был включен
                if loadGeneratorSettings.isEnabled && loadGeneratorSettings.autoStart {
                    startLoadGenerators()
                }
                
                save()
                updateSleepPrevention()
                updatePollingMode()
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
        // После загрузки применим политику сна в соответствии с восстановленным состоянием
        updateSleepPrevention()
    }

    /// Полная очистка персистентных данных анализа
    func clearPersistentData() {
        lastResult = nil
        recentResults.removeAll()
        samples.removeAll()
        lastSampleAt = nil
        state = .idle
        autoResetDueToGap = false
        let fm = FileManager.default
        try? fm.removeItem(at: storeURL)
        updateSleepPrevention()
    }

    /// Размер файла калибровки на диске (байт)
    var fileSizeBytes: Int64 {
        let fm = FileManager.default
        do {
            let attrs = try fm.attributesOfItem(atPath: storeURL.path)
            if let size = attrs[.size] as? NSNumber { return size.int64Value }
        } catch {
            // ignore
        }
        return 0
    }

    /// Включает/выключает запрет сна при активном тесте автоматически
    private func updateSleepPrevention() {
        // Автоматически предотвращаем сон только во время активного теста (running)
        let isRunning: Bool = {
            if case .running = state { return true } else { return false }
        }()
        if isRunning {
            beginPreventingSleepIfNeeded()
        } else {
            endPreventingSleepIfNeeded()
        }
    }

    private func beginPreventingSleepIfNeeded() {
        guard activity == nil else { return }
        let options: ProcessInfo.ActivityOptions = [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated]
        let token = ProcessInfo.processInfo.beginActivity(options: options, reason: "Battry test running")
        // Store opaque token in a type-erased container
        activity = token as NSObjectProtocol
    }

    private func endPreventingSleepIfNeeded() {
        if let token = activity {
            ProcessInfo.processInfo.endActivity(token)
        }
        activity = nil
    }

    // MARK: - CP Controller Setup
    private func setupCPController() {
        constantPowerController.setCallbacks(
            powerReading: { [weak self] in
                guard let self = self, let vm = self.batteryViewModel else { return 0 }
                return abs(vm.state.power)
            },
            loadControl: { [weak self] duty in
                guard let self = self else { return }
                // Управляем CPU‑генератором
                if duty <= 0.05 {
                    self.loadGenerator?.stop(reason: .userStopped)
                } else {
                    // Подбор профиля по duty
                    let profile: LoadProfile = duty < 0.4 ? .light : (duty < 0.7 ? .medium : .heavy)
                    self.loadGenerator?.start(profile: profile)
                }
            }
        )
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
    
    /// Обновляет режим опроса в зависимости от состояния калибровки
    private func updatePollingMode() {
        guard let vm = batteryViewModel else { return }
        
        switch state {
        case .waitingFull:
            // Ускоренный опрос при ожидании начала теста
            vm.enableFastMode()
        case .idle, .running, .paused, .completed:
            // Обычный опрос в остальных случаях
            vm.disableFastMode()
        }
    }
    
    // MARK: - Load Generator Management
    
    /// Запускает генераторы нагрузки согласно настройкам
    private func startLoadGenerators() {
        guard loadGeneratorSettings.isEnabled else { return }
        
        // Обновляем метаданные
        currentLoadMetadata = ReportGenerator.LoadGeneratorMetadata(
            wasUsed: true,
            profile: Localization.shared.t(loadGeneratorSettings.profile.localizationKey),
            autoStopReasons: []
        )
        
        // Запускаем CPU генератор
        loadGenerator?.start(profile: loadGeneratorSettings.profile)
        
        // Трекируем событие запуска CPU генератора
        historyStore?.addEvent(.generatorStarted, details: loadGeneratorSettings.profile.localizationKey)
        
        // Запускаем видео если включено
        // video load removed
        
        print("CalibrationEngine: Started load generators - CPU: \(loadGeneratorSettings.profile)")
    }
    
    /// Останавливает все генераторы нагрузки
    private func stopLoadGenerators() {
        if loadGenerator?.isRunning == true {
            loadGenerator?.stop(reason: .userStopped)
            // Трекируем событие остановки CPU генератора
            historyStore?.addEvent(.generatorStopped)
        }
        
        // video load removed
        
        print("CalibrationEngine: Stopped all load generators")
    }
    
    /// Сохраняет полные данные завершенного теста в отдельный файл
    private func saveTestData(result: CalibrationResult, samples: [BatteryReading], snapshot: BatterySnapshot) -> String? {
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // Создаем структуру данных для сохранения
        var testData: [String: Any] = [:]
        testData["test_id"] = String(timestamp)
        testData["started_at"] = ISO8601DateFormatter().string(from: result.startedAt)
        testData["finished_at"] = ISO8601DateFormatter().string(from: result.finishedAt)
        
        // Результаты калибровки
        testData["calibration_result"] = encode(result)
        
        // Метаданные генератора нагрузки (видео удалено)
        var loadMetadata: [String: Any] = [:]
        loadMetadata["isEnabled"] = loadGeneratorSettings.isEnabled
        loadMetadata["profile"] = loadGeneratorSettings.profile.localizationKey
        loadMetadata["autoStart"] = loadGeneratorSettings.autoStart
        testData["load_generator_metadata"] = loadMetadata
        
        // Все измерения за время теста
        testData["samples"] = samples.map { encode($0) }
        
        // Настройки теста
        var settings: [String: Any] = [:]
        settings["endThreshold"] = endThresholdPercent
        settings["maxResumeGap"] = maxResumeGap
        testData["settings"] = settings
        
        // Финальный снимок состояния батареи
        var finalSnapshot: [String: Any] = [:]
        finalSnapshot["percentage"] = snapshot.percentage
        finalSnapshot["voltage"] = snapshot.voltage
        finalSnapshot["temperature"] = snapshot.temperature
        finalSnapshot["isCharging"] = snapshot.isCharging
        finalSnapshot["powerSource"] = snapshot.powerSource.rawValue
        finalSnapshot["maxCapacity"] = snapshot.maxCapacity
        finalSnapshot["designCapacity"] = snapshot.designCapacity
        finalSnapshot["cycleCount"] = snapshot.cycleCount
        testData["final_snapshot"] = finalSnapshot
        
        // Определяем путь для сохранения (та же папка, что и history.json)
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let battryDir = base.appendingPathComponent("Battry", isDirectory: true)
        try? fm.createDirectory(at: battryDir, withIntermediateDirectories: true)
        
        let filename = "analyze_\(timestamp).json"
        let fileURL = battryDir.appendingPathComponent(filename)
        
        do {
            let data = try JSONSerialization.data(withJSONObject: testData, options: [.prettyPrinted])
            try data.write(to: fileURL, options: .atomic)
            print("CalibrationEngine: Saved test data to \(filename)")
            return fileURL.path
        } catch {
            alertManager.showSaveError(error, operation: "test data")
            return nil
        }
    }
    
    /// Структура для хранения загруженных данных теста
    struct TestData {
        let samples: [BatteryReading]
        let calibrationResult: CalibrationResult
        let finalSnapshot: BatterySnapshot
        let loadGeneratorMetadata: ReportGenerator.LoadGeneratorMetadata?
    }
    
    /// Загружает сохраненные данные теста из JSON файла
    func loadTestData(from path: String) -> TestData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let testData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            alertManager.showLoadError(FileError.fileNotFound, operation: "test data")
            return nil
        }
        
        // Загружаем samples
        guard let samplesArray = testData["samples"] as? [[String: Any]] else {
            alertManager.showLoadError(FileError.parseError, operation: "test samples")
            return nil
        }
        
        var samples: [BatteryReading] = []
        for sampleDict in samplesArray {
            if let sample: BatteryReading = decode(sampleDict) {
                samples.append(sample)
            }
        }
        
        // Загружаем calibration result
        guard let resultDict = testData["calibration_result"] as? [String: Any],
              let calibrationResult: CalibrationResult = decode(resultDict) else {
            alertManager.showLoadError(FileError.parseError, operation: "calibration result")
            return nil
        }
        
        // Загружаем final snapshot
        guard let snapshotDict = testData["final_snapshot"] as? [String: Any] else {
            alertManager.showLoadError(FileError.parseError, operation: "final snapshot")
            return nil
        }
        
        var finalSnapshot = BatterySnapshot()
        finalSnapshot.percentage = snapshotDict["percentage"] as? Int ?? 0
        finalSnapshot.voltage = snapshotDict["voltage"] as? Double ?? 0.0
        finalSnapshot.temperature = snapshotDict["temperature"] as? Double ?? 0.0
        finalSnapshot.isCharging = snapshotDict["isCharging"] as? Bool ?? false
        finalSnapshot.powerSource = PowerSource(rawValue: snapshotDict["powerSource"] as? String ?? "unknown") ?? .unknown
        finalSnapshot.maxCapacity = snapshotDict["maxCapacity"] as? Int ?? 0
        finalSnapshot.designCapacity = snapshotDict["designCapacity"] as? Int ?? 0
        finalSnapshot.cycleCount = snapshotDict["cycleCount"] as? Int ?? 0
        
        // Загружаем load generator metadata (опционально)
        var loadMetadata: ReportGenerator.LoadGeneratorMetadata? = nil
        if let metadataDict = testData["load_generator_metadata"] as? [String: Any] {
            let wasUsed = metadataDict["isEnabled"] as? Bool ?? false
            let profile = metadataDict["profile"] as? String
            loadMetadata = ReportGenerator.LoadGeneratorMetadata(
                wasUsed: wasUsed,
                profile: profile
            )
        }
        
        return TestData(
            samples: samples,
            calibrationResult: calibrationResult,
            finalSnapshot: finalSnapshot,
            loadGeneratorMetadata: loadMetadata
        )
    }
}
