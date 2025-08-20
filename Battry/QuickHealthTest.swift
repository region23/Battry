import Foundation
import Combine

/// Быстрый тест здоровья батареи на основе рекомендаций эксперта
/// Выполняет анализ за 30-40 минут вместо полной разрядки
@MainActor
final class QuickHealthTest: ObservableObject {
    
    /// Состояние быстрого теста
    enum TestState: Equatable {
        case idle
        case calibrating // калибровка в покое (2-3 мин)
        case pulseTesting(targetSOC: Int) // пульс-тест на определенном уровне SOC
        case energyWindow // измерение энергии 80→50%
        case analyzing // анализ результатов
        case completed(result: QuickHealthResult)
        case error(message: String)
        
        var isActive: Bool {
            switch self {
            case .idle, .completed, .error:
                return false
            default:
                return true
            }
        }
    }
    
    /// Режим нагрузки для пульс-тестов
    enum LoadLevel: CaseIterable {
        case off
        case light
        case medium
        case heavy
        
        var localizationKey: String {
            switch self {
            case .off: return "load.off"
            case .light: return "load.light"
            case .medium: return "load.medium"
            case .heavy: return "load.heavy"
            }
        }
    }
    
    /// Результат быстрого теста здоровья
    struct QuickHealthResult: Codable, Equatable {
        let startedAt: Date
        let completedAt: Date
        let durationMinutes: Double
        
        // Энергетические метрики
        let energyDelivered80to50Wh: Double
        let sohEnergy: Double // %
        let averagePower: Double // W
        let targetPower: Double // W (целевая мощность для CP-теста)
        let powerPreset: String // используемый пресет (0.1C/0.2C/0.3C)
        
        // DCIR метрики
        let dcirPoints: [DCIRCalculator.DCIRPoint]
        let dcirAt50Percent: Double?
        let dcirAt20Percent: Double?
        
        // OCV анализ
        let kneeSOC: Double?
        let kneeIndex: Double
        
        // Стабильность
        let microDropCount: Int
        let microDropCountAbove20: Int
        let microDropCountBelow20: Int
        let microDropRatePerHour: Double
        let microDropRateAbove20PerHour: Double
        let microDropRateBelow20PerHour: Double
        let unstableUnderLoad: Bool
        let stabilityScore: Double // 0-100
        
        // Температурная нормализация
        let averageTemperature: Double
        let normalizedSOH: Double // температурно-нормализованный SOH
        let temperatureQuality: Double // качество температурных условий
        
        // CP контроль качества
        let powerControlQuality: Double // качество поддержания постоянной мощности
        
        // Композитный скор здоровья
        let healthScore: Double // 0-100
        let recommendation: String
        
        var isHealthy: Bool { healthScore >= 70 }
        var needsAttention: Bool { healthScore < 70 && healthScore >= 50 }
        var critical: Bool { healthScore < 50 }
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var state: TestState = .idle
    @Published private(set) var currentStep: String = ""
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var estimatedTimeRemaining: TimeInterval?
    @Published private(set) var lastResult: QuickHealthResult?
    
    // MARK: - Private Properties
    
    private var samples: [BatteryReading] = []
    private var dcirMeasurements: [DCIRCalculator.DCIRPoint] = []
    // Энергетическое окно: суммируем только интервалы CP
    private var cpIntervals: [(startIdx: Int, endIdx: Int?)] = []
    private var energyWindowTargetSOC: Int? = nil
    private var cpPhase: Int = 0 // 0: not started, 1: 80→60, 2: 60→50
    private var baselineStartAt: Date? = nil
    private var requireWindow95to90: Bool = false
    
    private weak var batteryViewModel: BatteryViewModel?
    private weak var loadGenerator: LoadGenerator?
    private weak var calibrationEngine: CalibrationEngine?
    // Video load removed
    
    // Constant Power контроль
    private lazy var constantPowerController = ConstantPowerController()
    private var selectedPowerPreset: PowerPreset = .medium
    private var targetPowerW: Double = 10.0
    
    private var cancellables = Set<AnyCancellable>()
    private let testTargetSOCs = [80, 60, 40, 20] // Уровни SOC для пульс-тестов
    private var currentTargetIndex = 0
    private let alertManager = AlertManager.shared
    
    // Progress tracking
    private var testStartTime: Date?
    private var currentPulseIndex = 0
    private var totalPulsesPerSOC = 3 // light, medium, heavy
    private var averageDischargeRatePercentPerMinute: Double = 0.5 // estimated default
    
    // Настройки теста
    private let calibrationDurationSec: TimeInterval = 150 // 2.5 мин калибровка в покое
    private let pulseDurationSec: TimeInterval = 10 // 10 сек пульс нагрузки
    private let restDurationSec: TimeInterval = 25 // 25 сек отдых между пульсами
    // Конфигурируемая ширина энергетического окна в процентах SOC (по умолчанию 30% → окно 80→50)
    private let energyWindowSpanPct: Int = 30
    
    // MARK: - File Storage
    
    /// Путь к директории с данными Quick Health Test
    private static var appSupportDir: URL {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Battry", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Путь к файлу с историей результатов
    private static var resultsHistoryURL: URL {
        return appSupportDir.appendingPathComponent("quickhealth_results.json")
    }
    
    /// Создает имя файла для отдельного результата теста
    private static func resultFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "quickhealth_\(formatter.string(from: date)).json"
    }
    
    // MARK: - Public Methods
    
    /// Привязывает необходимые зависимости
    func bind(
        batteryViewModel: BatteryViewModel,
        loadGenerator: LoadGenerator,
        calibrationEngine: CalibrationEngine? = nil
    ) {
        self.batteryViewModel = batteryViewModel
        self.loadGenerator = loadGenerator
        self.calibrationEngine = calibrationEngine
        
        // Настраиваем ConstantPowerController
        setupConstantPowerController()
        
        // Подписываемся на обновления батареи
        batteryViewModel.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleBatteryUpdate(snapshot)
            }
            .store(in: &cancellables)
        
        // Загружаем последний результат из хранилища
        initializeFromStorage()
    }
    
    /// Устанавливает пресет мощности для теста
    func setPowerPreset(_ preset: PowerPreset) {
        guard state == .idle else { return }
        selectedPowerPreset = preset
    }
    
    /// Запускает быстрый тест здоровья
    func start() {
        guard state == .idle else { return }
        
        // Проверяем, что не запущен полный тест
        if let calibrator = calibrationEngine, calibrator.state.isActive {
            state = .error(message: "Cannot start quick test: full battery test is running")
            return
        }
        
        // Проверяем предварительные условия
        guard let vm = batteryViewModel else {
            state = .error(message: "Battery monitoring not available")
            return
        }
        
        let currentSOC = vm.state.percentage
        guard currentSOC >= 85 else {
            state = .error(message: "Battery must be charged to at least 85% before starting test")
            return
        }
        
        // Строго проверяем питание: должен быть режим от батареи (не от сети)
        guard vm.state.powerSource == .battery else {
            state = .error(message: "Please disconnect power adapter before starting test")
            return
        }
        
        guard !vm.state.isCharging else {
            state = .error(message: "Please disconnect power adapter before starting test")
            return
        }
        
        // Вычисляем целевую мощность для выбранного пресета
        targetPowerW = PowerCalculator.targetPower(
            for: selectedPowerPreset,
            designCapacityMah: vm.state.designCapacity
        )
        
        // Включаем высокочастотный режим опроса (1 Гц)
        vm.enableTestMode()
        
        // Инициализируем тест
        samples.removeAll()
        dcirMeasurements.removeAll()
        currentTargetIndex = 0
        progress = 0.0
        cpIntervals.removeAll()
        energyWindowTargetSOC = nil
        cpPhase = 0
        
        // Initialize progress tracking
        testStartTime = Date()
        currentPulseIndex = 0
        estimatedTimeRemaining = nil
        
        // Определяем необходимость ожидания окна 95–90% для baseline
        requireWindow95to90 = (currentSOC > 95)
        state = .calibrating
        baselineStartAt = nil
        if requireWindow95to90 {
            currentStep = "Waiting for 95–90% SOC window (current: \(currentSOC)%)"
        } else if currentSOC >= 90 {
            currentStep = "Baseline at rest (2–3 min) in 95–90% window…"
        } else {
            currentStep = "Baseline at rest (2–3 min)…"
        }
    }
    
    /// Останавливает тест
    func stop() {
        // Останавливаем Constant Power контроллер
        constantPowerController.stop()
        
        // Останавливаем генераторы нагрузки
        loadGenerator?.stop(reason: .userStopped)
        
        // Возвращаем обычный режим опроса
        batteryViewModel?.disableTestMode()
        
        state = .idle
        currentStep = ""
        progress = 0.0
        estimatedTimeRemaining = nil
        
        // Reset tracking variables
        testStartTime = nil
        currentPulseIndex = 0
        
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func updateTimeEstimation(currentSOC: Int) {
        guard let startTime = testStartTime else {
            estimatedTimeRemaining = nil
            return
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Calculate remaining work based on current state
        var remainingTime: TimeInterval = 0
        
        switch state {
        case .calibrating:
            if let baselineStart = baselineStartAt {
                let remainingCalibration = max(0, calibrationDurationSec - Date().timeIntervalSince(baselineStart))
                remainingTime += remainingCalibration
            }
            // Add time for all pulse tests and energy window
            remainingTime += estimateTimeForAllPulseTests(fromSOC: currentSOC)
            remainingTime += estimateTimeForEnergyWindow(fromSOC: currentSOC)
            
        case .pulseTesting(let targetSOC):
            let targetIndex = testTargetSOCs.firstIndex(of: targetSOC) ?? 0
            
            if currentSOC > targetSOC {
                // Time to wait for battery to discharge to target
                let socDiff = Double(currentSOC - targetSOC)
                updateDischargeRate(currentSOC: currentSOC, elapsedTime: elapsedTime)
                remainingTime += (socDiff / averageDischargeRatePercentPerMinute) * 60
            }
            
            // Add time for pulse tests at this and remaining SOC levels
            remainingTime += estimateTimeForPulseTests(fromIndex: targetIndex)
            remainingTime += estimateTimeForEnergyWindow(fromSOC: currentSOC)
            
        case .energyWindow:
            if let targetSOC = energyWindowTargetSOC {
                let socDiff = Double(currentSOC - targetSOC)
                remainingTime += (socDiff / averageDischargeRatePercentPerMinute) * 60
            }
            // Add remaining pulse tests after energy window
            remainingTime += estimateTimeForPulseTests(fromIndex: 1) // from 60% onwards
            
        case .analyzing:
            remainingTime = 30 // analysis typically takes ~30 seconds
            
        default:
            remainingTime = 0
        }
        
        estimatedTimeRemaining = max(30, remainingTime) // minimum 30 seconds
    }
    
    private func updateDischargeRate(currentSOC: Int, elapsedTime: TimeInterval) {
        guard samples.count >= 2, elapsedTime > 60 else { return } // need at least 1 minute of data
        
        let recentSamples = samples.suffix(min(30, samples.count)) // last 30 samples
        if let firstRecent = recentSamples.first, let lastRecent = recentSamples.last {
            let timeDiff = lastRecent.timestamp.timeIntervalSince(firstRecent.timestamp) / 60.0 // minutes
            let socDiff = Double(firstRecent.percentage - lastRecent.percentage)
            
            if timeDiff > 0 && socDiff > 0 {
                let newRate = socDiff / timeDiff
                // Smooth the rate with exponential moving average
                averageDischargeRatePercentPerMinute = 0.3 * newRate + 0.7 * averageDischargeRatePercentPerMinute
            }
        }
    }
    
    private func estimateTimeForAllPulseTests(fromSOC: Int) -> TimeInterval {
        var totalTime: TimeInterval = 0
        
        for (_, targetSOC) in testTargetSOCs.enumerated() {
            if fromSOC > targetSOC {
                // Time to discharge to this SOC level
                let socDiff = Double(fromSOC - targetSOC)
                totalTime += (socDiff / averageDischargeRatePercentPerMinute) * 60
            }
            
            // Time for pulse tests at this level
            totalTime += estimateTimeForPulseTestsAtLevel()
        }
        
        return totalTime
    }
    
    private func estimateTimeForPulseTests(fromIndex: Int) -> TimeInterval {
        let remainingLevels = max(0, testTargetSOCs.count - fromIndex)
        return Double(remainingLevels) * estimateTimeForPulseTestsAtLevel()
    }
    
    private func estimateTimeForPulseTestsAtLevel() -> TimeInterval {
        // 3 pulses × (10 sec pulse + 25 sec rest) = 105 seconds
        return Double(totalPulsesPerSOC) * (pulseDurationSec + restDurationSec)
    }
    
    private func estimateTimeForEnergyWindow(fromSOC: Int) -> TimeInterval {
        if fromSOC > 50 { // energy window is 80->50
            let socDiff = Double(max(0, fromSOC - 50))
            return (socDiff / averageDischargeRatePercentPerMinute) * 60
        }
        return 0
    }
    
    private func handleBatteryUpdate(_ snapshot: BatterySnapshot) {
        let reading = BatteryReading(
            timestamp: Date(),
            percentage: snapshot.percentage,
            isCharging: snapshot.isCharging,
            voltage: snapshot.voltage,
            temperature: snapshot.temperature,
            maxCapacity: snapshot.maxCapacity,
            designCapacity: snapshot.designCapacity,
            amperage: snapshot.amperage
        )
        
        samples.append(reading)
        
        // Update time estimation
        updateTimeEstimation(currentSOC: snapshot.percentage)
        
        // Обрабатываем состояние теста
        switch state {
        case .calibrating:
            let soc = snapshot.percentage
            // Ожидание окна 95–90% при старте выше 95%
            if requireWindow95to90 && (baselineStartAt == nil) {
                if soc > 95 {
                    currentStep = "Waiting for 95–90% SOC window (current: \(soc)%)"
                    break
                } else if soc >= 90 { // вошли в окно — стартуем baseline
                    baselineStartAt = Date()
                    currentStep = "Baseline at rest (2–3 min) in 95–90% window…"
                } else { // прошли ниже 90% до начала — запускаем baseline сразу
                    baselineStartAt = Date()
                    currentStep = "Baseline at rest (2–3 min)…"
                }
            }

            // Если baseline ещё не начат и окно не требуется, проверяем SOC
            if !requireWindow95to90 && baselineStartAt == nil {
                if soc >= 90 {
                    baselineStartAt = Date()
                    currentStep = "Baseline at rest (2–3 min) in 95–90% window…"
                } else {
                    // Нет окна — пропускаем baseline
                    state = .pulseTesting(targetSOC: testTargetSOCs[0])
                    break
                }
            }

            // Ведём baseline, если стартовал
            if let t0 = baselineStartAt {
                let elapsed = Date().timeIntervalSince(t0)
                let ratio = min(1.0, elapsed / calibrationDurationSec)
                // Ограничиваем вклад baseline в общий прогресс первыми 20%
                progress = max(progress, 0.2 * ratio)
                if elapsed >= calibrationDurationSec {
                    // Переходим к пульсам на 80%
                    state = .pulseTesting(targetSOC: testTargetSOCs[0])
                    progress = max(progress, 0.2)
                    baselineStartAt = nil
                }
            }
            
        case .pulseTesting(let targetSOC):
            handlePulseTestState(targetSOC: targetSOC, snapshot: snapshot)
            
        case .energyWindow:
            handleEnergyWindowState(snapshot: snapshot)
            
        default:
            break
        }
    }
    
    private func handlePulseTestState(targetSOC: Int, snapshot: BatterySnapshot) {
        let currentSOC = snapshot.percentage
        
        // Ждем пока батарея разрядится до целевого SOC
        if currentSOC > targetSOC {
            currentStep = String(format: NSLocalizedString("quick.test.waiting.soc", comment: ""), targetSOC, currentSOC)
            return
        }
        
        // Выполняем серию пульс-тестов на этом уровне SOC
        performPulseTests(at: targetSOC) {
            // Ветка CP-окна: единожды на уровне 80% в соответствии с span
            if targetSOC == 80 {
                let target = max(5, 80 - self.energyWindowSpanPct)
                self.startEnergyWindow(to: target)
                return
            }

            // Обычное продвижение по целям SOC
            self.currentTargetIndex += 1
            if self.currentTargetIndex < self.testTargetSOCs.count {
                let nextTargetSOC = self.testTargetSOCs[self.currentTargetIndex]
                self.state = .pulseTesting(targetSOC: nextTargetSOC)
                self.progress = 0.3 + Double(self.currentTargetIndex) * 0.15
            } else {
                // Пульсы завершены — переходим к анализу
                self.analyzeResults()
            }
        }
    }
    
    private func performPulseTests(at socLevel: Int, completion: @escaping () -> Void) {
        currentPulseIndex = 0
        
        // Запускаем последовательность: light → medium → heavy → off
        var pulseIndex = 0
        let loadLevels: [LoadLevel] = [.light, .medium, .heavy]
        let loadNames = ["light", "medium", "heavy"]
        
        func runNextPulse() {
            guard pulseIndex < loadLevels.count else {
                currentStep = String(format: NSLocalizedString("quick.test.completed.soc", comment: ""), socLevel)
                completion()
                return
            }
            
            let loadLevel = loadLevels[pulseIndex]
            let loadName = loadNames[pulseIndex]
            currentPulseIndex = pulseIndex
            
            // Update detailed status
            currentStep = String(format: NSLocalizedString("quick.test.pulse.progress", comment: ""), pulseIndex + 1, loadLevels.count, NSLocalizedString("load.level.\(loadName)", comment: ""), socLevel)
            
            let pulseStartIndex = samples.count - 1
            
            // Включаем нагрузку
            applyLoad(loadLevel)
            
            // Через 10 секунд выключаем нагрузку и измеряем DCIR
            DispatchQueue.main.asyncAfter(deadline: .now() + pulseDurationSec) {
                self.applyLoad(.off)
                self.currentStep = String(format: NSLocalizedString("quick.test.resting", comment: ""), NSLocalizedString("load.level.\(loadName)", comment: ""), Int(self.restDurationSec))
                
                // Измеряем DCIR
                if let dcirPoint = DCIRCalculator.estimateDCIR(
                    samples: self.samples,
                    pulseStartIndex: pulseStartIndex,
                    windowSeconds: 3.0
                ) {
                    self.dcirMeasurements.append(dcirPoint)
                }
                
                // Update progress within this SOC level
                let socLevelProgress = Double(pulseIndex + 1) / Double(loadLevels.count)
                let baseProgress = 0.2 + Double(self.currentTargetIndex) * 0.15
                self.progress = baseProgress + (0.15 * socLevelProgress)
                
                // Отдыхаем 25 секунд перед следующим пульсом
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restDurationSec) {
                    pulseIndex += 1
                    runNextPulse()
                }
            }
        }
        
        runNextPulse()
    }
    
    private func startEnergyWindow(to targetSOC: Int) {
        energyWindowTargetSOC = targetSOC
        state = .energyWindow
        cpPhase = 1
        currentStep = "Energy window CP to \(targetSOC)% @ \(String(format: "%.1f", targetPowerW))W"
        progress = max(progress, 0.7)
        // Фиксируем начало CP-интервала
        cpIntervals.append((startIdx: samples.count, endIdx: nil))
        // Запускаем Constant Power контроллер
        constantPowerController.start(targetPower: targetPowerW)
    }
    
    private func handleEnergyWindowState(snapshot: BatterySnapshot) {
        let currentSOC = snapshot.percentage
        guard let targetSOC = energyWindowTargetSOC else { return }

        if currentSOC <= targetSOC {
            // Завершаем текущий CP-сегмент
            constantPowerController.stop()
            // Закрываем последний CP-интервал
            if let idx = cpIntervals.indices.last, cpIntervals[idx].endIdx == nil {
                cpIntervals[idx].endIdx = samples.count
            }
            progress = max(progress, targetSOC == 60 ? 0.75 : 0.9)

            // После завершения окна CP продолжаем пульсы на 60%
            state = .pulseTesting(targetSOC: 60)
            energyWindowTargetSOC = nil
        } else {
            currentStep = "Energy window CP: \(currentSOC)% → \(targetSOC)% | \(String(format: "%.1f", constantPowerController.currentPowerW))W"
        }
    }
    
    private func analyzeResults() {
        state = .analyzing
        currentStep = "Analyzing test results..."
        progress = 0.95
        
        Task {
            let result = await Task { @MainActor in
                self.performAnalysis()
            }.value
            
            await MainActor.run {
                self.lastResult = result
                self.state = .completed(result: result)
                self.currentStep = "Test completed"
                self.progress = 1.0
                
                // Автоматически сохраняем результат
                self.saveResult(result)
            }
        }
    }
    
    private func performAnalysis() -> QuickHealthResult {
        let startTime = samples.first?.timestamp ?? Date()
        let endTime = Date()
        let durationMinutes = endTime.timeIntervalSince(startTime) / 60.0
        
        // Анализ энергии только по CP-интервалам
        var energyWhTotal: Double = 0
        var cpDurationSec: Double = 0
        var collectedSocSpan: Double = 0
        for interval in cpIntervals {
            guard let endIdx = interval.endIdx, interval.startIdx < endIdx, endIdx <= samples.count else { continue }
            let slice = Array(samples[interval.startIdx..<endIdx])
            energyWhTotal += EnergyCalculator.integrateEnergy(samples: slice)
            if let f = slice.first, let l = slice.last {
                cpDurationSec += l.timestamp.timeIntervalSince(f.timestamp)
                collectedSocSpan += max(0, Double(f.percentage - l.percentage))
            }
        }
        let avgPowerDuringCP = cpDurationSec > 0 ? energyWhTotal / (cpDurationSec / 3600.0) : 0
        // Оценка SOH_energy: масштабируем на 100% по фактическому SOC-окну
        let designMah = samples.last?.designCapacity ?? batteryViewModel?.state.designCapacity ?? 0
        // Среднее V_OC из OCV-кривой (если доступно), fallback 11.1 В
        let ocvForAvg = OCVAnalyzer(dcirPoints: dcirMeasurements).analyzeOCV(from: samples).ocvCurve
        let avgVOC: Double = ocvForAvg.isEmpty ? 11.1 : max(5.0, ocvForAvg.map { $0.ocvVoltage }.reduce(0, +) / Double(ocvForAvg.count))
        let designWh = Double(designMah) * avgVOC / 1000.0
        let socSpan = max(1.0, collectedSocSpan)
        let estimatedFullEnergyWh = energyWhTotal * (100.0 / socSpan)
        let sohEnergyPct = (designWh > 0) ? max(0, min(100, (estimatedFullEnergyWh / designWh) * 100.0)) : 100.0
        
        // Анализ DCIR
        let dcirAnalysis = DCIRCalculator.analyzeDCIR(dcirPoints: dcirMeasurements)
        
        // Анализ OCV
        let ocvAnalyzer = OCVAnalyzer(dcirPoints: dcirMeasurements)
        let ocvAnalysis = ocvAnalyzer.analyzeOCV(from: samples)
        
        // Подсчет микро-дропов (общий и по SOC-диапазонам)
        let microStats = computeMicroDropStats(samples: samples)
        let microDrops = microStats.totalCount
        let stabilityScore = calculateStabilityScore(microDrops: microDrops, samples: samples)
        let microDropRate = microStats.totalRatePerHour
        let unstable = hasMicroDropsAboveSOC(samples: samples, thresholdPct: 2, windowSec: 120, socMin: 20)
        
        // Температурный анализ
        let temperatures = samples.map(\.temperature)
        let avgTemperature = temperatures.reduce(0, +) / Double(max(1, temperatures.count))
        let tempQuality = TemperatureNormalizer.temperatureQuality(avgTemperature)
        
        // Температурная нормализация
        let tempNormalization = TemperatureNormalizer.normalize(
            sohEnergy: sohEnergyPct,
            dcirAt50: dcirAnalysis.dcirAt50Percent,
            averageTemperature: avgTemperature
        )
        // Записываем наблюдение для самообучения температурной нормализации
        TemperatureNormalizer.recordObservation(
            sohEnergy: sohEnergyPct,
            dcirAt50: dcirAnalysis.dcirAt50Percent,
            temperature: avgTemperature
        )
        
        // SOH по емкости (из последних данных)
        let lastDesign = samples.last?.designCapacity ?? batteryViewModel?.state.designCapacity ?? 0
        let lastMax = samples.last?.maxCapacity ?? batteryViewModel?.state.maxCapacity ?? 0
        let sohCapacityPct: Double = (lastDesign > 0 && lastMax > 0) ? min(100, max(0, Double(lastMax) / Double(lastDesign) * 100.0)) : 100.0

        // Композитный скор здоровья (по формуле эксперта)
        let healthScore = calculateCompositeHealthScore(
            sohEnergy: tempNormalization.normalizedSOH,
            sohCapacity: sohCapacityPct,
            dcirAt50: tempNormalization.normalizedDCIR,
            dcirAt20: dcirAnalysis.dcirAt20Percent,
            stabilityScore: stabilityScore,
            temperatureQuality: tempQuality
        )
        
        // Рекомендация
        let recommendation = generateRecommendation(healthScore: healthScore)
        
        return QuickHealthResult(
            startedAt: startTime,
            completedAt: endTime,
            durationMinutes: durationMinutes,
            energyDelivered80to50Wh: energyWhTotal,
            sohEnergy: sohEnergyPct,
            averagePower: avgPowerDuringCP,
            targetPower: targetPowerW,
            powerPreset: selectedPowerPreset.rawValue,
            dcirPoints: dcirMeasurements,
            dcirAt50Percent: dcirAnalysis.dcirAt50Percent,
            dcirAt20Percent: dcirAnalysis.dcirAt20Percent,
            kneeSOC: ocvAnalysis.kneeSOC,
            kneeIndex: ocvAnalysis.kneeIndex,
            microDropCount: microDrops,
            microDropCountAbove20: microStats.countAbove20,
            microDropCountBelow20: microStats.countBelow20,
            microDropRatePerHour: microDropRate,
            microDropRateAbove20PerHour: microStats.rateAbove20PerHour,
            microDropRateBelow20PerHour: microStats.rateBelow20PerHour,
            unstableUnderLoad: unstable,
            stabilityScore: stabilityScore,
            averageTemperature: avgTemperature,
            normalizedSOH: tempNormalization.normalizedSOH,
            temperatureQuality: tempQuality,
            powerControlQuality: constantPowerController.controlQuality,
            healthScore: healthScore,
            recommendation: recommendation
        )
    }
    
    private func calculateCompositeHealthScore(
        sohEnergy: Double,
        sohCapacity: Double,
        dcirAt50: Double?,
        dcirAt20: Double?,
        stabilityScore: Double,
        temperatureQuality: Double
    ) -> Double {
        // Формула эксперта: 40% SOH_energy + 25% DCIR + 20% SOH_capacity + 10% стабильность + 5% температура
        var score: Double = 0
        // 40% - SOH по энергии
        score += 0.4 * sohEnergy
        // 25% - DCIR оценка (чем выше, тем хуже)
        var dcirScore: Double = 100
        if let dcir50 = dcirAt50 { dcirScore = max(0, 100 - (dcir50 - 100) / 2) }
        if let dcir20 = dcirAt20 {
            let dcir20Score = max(0, 100 - (dcir20 - 200) / 3)
            dcirScore = (dcirScore + dcir20Score) / 2
        }
        score += 0.25 * dcirScore
        // 20% - SOH по емкости
        score += 0.2 * sohCapacity
        // 10% - стабильность
        score += 0.1 * stabilityScore
        // 5% - температурная терпимость
        score += 0.05 * max(0, min(100, temperatureQuality))
        return max(0, min(100, score))
    }
    
    private func countMicroDrops(in samples: [BatteryReading]) -> Int {
        guard samples.count >= 2 else { return 0 }
        
        var dropCount = 0
        
        for i in 1..<samples.count {
            let prev = samples[i-1]
            let curr = samples[i]
            
            let timeDiff = curr.timestamp.timeIntervalSince(prev.timestamp)
            let percentDrop = prev.percentage - curr.percentage
            
            if !curr.isCharging && !prev.isCharging && timeDiff <= 120 && percentDrop >= 2 {
                dropCount += 1
            }
        }
        
        return dropCount
    }
    
    /// Возвращает статистику микро‑дропов по SOC диапазонам
    private func computeMicroDropStats(samples: [BatteryReading]) -> (totalCount: Int, countAbove20: Int, countBelow20: Int, totalRatePerHour: Double, rateAbove20PerHour: Double, rateBelow20PerHour: Double) {
        guard samples.count >= 2 else { return (0,0,0,0,0,0) }
        // Подсчитаем длительности по диапазонам SOC
        var durationAbove20: Double = 0 // hours
        var durationBelow20: Double = 0 // hours
        for i in 1..<samples.count {
            let prev = samples[i-1]
            let curr = samples[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp) / 3600.0
            guard dt > 0, !prev.isCharging && !curr.isCharging else { continue }
            if prev.percentage >= 20 { durationAbove20 += dt } else { durationBelow20 += dt }
        }
        // События со скользящим окном ≤120 c
        var total = 0
        var above20 = 0
        var below20 = 0
        var i = 0
        while i < samples.count {
            let start = samples[i]
            if start.isCharging { i += 1; continue }
            var j = i + 1
            var found = false
            while j < samples.count {
                let dt = samples[j].timestamp.timeIntervalSince(start.timestamp)
                if dt > 120 { break }
                if !samples[j].isCharging {
                    let drop = start.percentage - samples[j].percentage
                    if drop >= 2 {
                        total += 1
                        if start.percentage >= 20 { above20 += 1 } else { below20 += 1 }
                        found = true
                        break
                    }
                }
                j += 1
            }
            i = found ? j : (i + 1)
        }
        let totalDuration = max(1e-6, durationAbove20 + durationBelow20)
        let totalRate = Double(total) / totalDuration
        let rateAbove = durationAbove20 > 0 ? Double(above20) / durationAbove20 : 0
        let rateBelow = durationBelow20 > 0 ? Double(below20) / durationBelow20 : 0
        return (total, above20, below20, totalRate, rateAbove, rateBelow)
    }
    private func hasMicroDropsAboveSOC(samples: [BatteryReading], thresholdPct: Int, windowSec: Double, socMin: Int) -> Bool {
        guard samples.count >= 2 else { return false }
        var i = 0
        while i < samples.count {
            let start = samples[i]
            if start.isCharging || start.percentage < socMin { i += 1; continue }
            var j = i + 1
            while j < samples.count {
                let dt = samples[j].timestamp.timeIntervalSince(start.timestamp)
                if dt > windowSec { break }
                if !samples[j].isCharging {
                    let drop = start.percentage - samples[j].percentage
                    if drop >= thresholdPct { return true }
                }
                j += 1
            }
            i += 1
        }
        return false
    }
    
    private func calculateStabilityScore(microDrops: Int, samples: [BatteryReading]) -> Double {
        if samples.isEmpty { return 100 }
        
        let durationHours = max(1, samples.last!.timestamp.timeIntervalSince(samples.first!.timestamp) / 3600.0)
        let dropsPerHour = Double(microDrops) / durationHours
        
        // Хорошая стабильность: <1 дроп/час, плохая: >3 дропов/час
        return max(0, min(100, 100 - dropsPerHour * 25))
    }
    
    private func generateRecommendation(healthScore: Double) -> String {
        switch healthScore {
        case 85...:
            return "Battery health is excellent. No action required."
        case 70..<85:
            return "Battery health is good. Monitor periodically."
        case 50..<70:
            return "Battery health is fair. Consider replacement planning."
        default:
            return "Battery health is poor. Replacement recommended soon."
        }
    }
    
    private func applyLoad(_ level: LoadLevel) {
        switch level {
        case .off:
            loadGenerator?.stop(reason: .userStopped)
        case .light:
            loadGenerator?.start(profile: .light)
        case .medium:
            loadGenerator?.start(profile: .medium)
        case .heavy:
            loadGenerator?.start(profile: .heavy)
        }
    }
    
    private func scheduleStateChange(to newState: TestState, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.state = newState
        }
    }
    
    /// Настраивает Constant Power контроллер
    private func setupConstantPowerController() {
        constantPowerController.setCallbacks(
            powerReading: { [weak self] in
                // Читаем текущую мощность из BatteryViewModel
                guard let self = self,
                      let vm = self.batteryViewModel else { return 0 }
                return abs(vm.state.power)
            },
            loadControl: { [weak self] dutyCycle in
                // Управляем нагрузкой через LoadGenerator (интенсивность + профиль)
                guard let self = self, let loadGen = self.loadGenerator else { return }
                // Поддерживаем профиль согласно целевой мощности
                if let rec = self.constantPowerController.getRecommendedLoadIntensity() {
                    loadGen.ensureProfile(rec.profile)
                    loadGen.setIntensity(rec.intensity)
                } else {
                    // Fallback: light/medium/heavy по duty
                    self.applyLoadWithDutyCycle(dutyCycle)
                }
            }
        )
    }
    
    /// Применяет нагрузку с заданным duty cycle
    private func applyLoadWithDutyCycle(_ dutyCycle: Double) {
        guard let loadGen = loadGenerator else { return }
        
        // Получаем рекомендацию от ConstantPowerController
        if let recommendation = constantPowerController.getRecommendedLoadIntensity() {
            if recommendation.shouldUpdate {
                applyLoadRecommendation(recommendation: recommendation, loadGenerator: loadGen)
            }
        } else {
            // Fallback: простое управление по duty cycle
            applySimpleLoad(dutyCycle: dutyCycle, loadGenerator: loadGen)
        }
    }
    
    /// Применяет рекомендацию от ConstantPowerController
    private func applyLoadRecommendation(recommendation: LoadIntensityRecommendation, loadGenerator: LoadGenerator) {
        if recommendation.intensity < 0.05 {
            loadGenerator.stop(reason: .userStopped)
        } else {
            // LoadGenerator пока не поддерживает точное управление интенсивностью
            // Используем временное управление для имитации точной интенсивности
            applyTemporalControl(
                profile: recommendation.profile, 
                dutyCycle: recommendation.dutyCycle,
                loadGenerator: loadGenerator
            )
        }
    }
    
    /// Простое управление по duty cycle (fallback)
    private func applySimpleLoad(dutyCycle: Double, loadGenerator: LoadGenerator) {
        if dutyCycle < 0.1 {
            loadGenerator.stop(reason: .userStopped)
        } else {
            // Выбираем профиль на основе duty cycle
            let profile: LoadProfile
            if dutyCycle < 0.4 {
                profile = .light
            } else if dutyCycle < 0.7 {
                profile = .medium
            } else {
                profile = .heavy
            }
            
            loadGenerator.start(profile: profile)
        }
    }
    
    /// Временное управление для имитации точной интенсивности
    private func applyTemporalControl(profile: LoadProfile, dutyCycle: Double, loadGenerator: LoadGenerator) {
        // Используем цикл 10 секунд для точного duty cycle
        let cycleLength: TimeInterval = 10.0
        let onTime = cycleLength * dutyCycle
        let offTime = cycleLength * (1.0 - dutyCycle)
        
        // Включаем нагрузку
        loadGenerator.start(profile: profile)
        
        // Планируем временное выключение только если duty cycle < 0.9
        if dutyCycle < 0.9 && offTime > 0.5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + onTime) { [weak self] in
                guard let self = self, 
                      case .energyWindow = self.state else { return }
                
                loadGenerator.stop(reason: .userStopped)
                
                // Планируем повторное включение
                DispatchQueue.main.asyncAfter(deadline: .now() + offTime) { [weak self] in
                    guard let self = self,
                          case .energyWindow = self.state else { return }
                    
                    // Повторяем цикл
                    self.applyTemporalControl(profile: profile, dutyCycle: dutyCycle, loadGenerator: loadGenerator)
                }
            }
        }
    }
    
    // MARK: - Results Storage
    
    /// Сохраняет результат теста в JSON файлы
    private func saveResult(_ result: QuickHealthResult) {
        // Сохраняем отдельный файл для этого теста
        let fileName = Self.resultFileName(for: result.startedAt)
        let fileURL = Self.appSupportDir.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            try data.write(to: fileURL)
            print("Quick health test result saved to: \(fileURL.path)")
        } catch {
            alertManager.showSaveError(error, operation: "quick health test result")
        }
        
        // Обновляем историю результатов
        updateResultsHistory(with: result)
    }
    
    /// Обновляет файл с историей всех результатов
    private func updateResultsHistory(with newResult: QuickHealthResult) {
        var results = loadResults()
        
        // Добавляем новый результат
        results.append(newResult)
        
        // Сортируем по дате (новые сначала)
        results.sort { $0.startedAt > $1.startedAt }
        
        // Ограничиваем количество результатов (например, последние 50)
        if results.count > 50 {
            results = Array(results.prefix(50))
        }
        
        // Сохраняем обновленную историю
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(results)
            try data.write(to: Self.resultsHistoryURL)
        } catch {
            alertManager.showSaveError(error, operation: "quick health test history")
        }
    }
    
    /// Загружает историю всех результатов
    func loadResults() -> [QuickHealthResult] {
        guard FileManager.default.fileExists(atPath: Self.resultsHistoryURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: Self.resultsHistoryURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([QuickHealthResult].self, from: data)
        } catch {
            alertManager.showLoadError(error, operation: "quick health test results")
            return []
        }
    }
    
    /// Загружает последний результат
    func loadLastResult() -> QuickHealthResult? {
        return loadResults().first
    }
    
    /// Инициализирует последний результат при старте
    func initializeFromStorage() {
        lastResult = loadLastResult()
    }
}