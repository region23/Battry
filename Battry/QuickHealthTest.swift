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
    struct QuickHealthResult: Codable {
        let startedAt: Date
        let completedAt: Date
        let durationMinutes: Double
        
        // Энергетические метрики
        let energyDelivered80to50Wh: Double
        let sohEnergy: Double // %
        let averagePower: Double // W
        
        // DCIR метрики
        let dcirPoints: [DCIRCalculator.DCIRPoint]
        let dcirAt50Percent: Double?
        let dcirAt20Percent: Double?
        
        // OCV анализ
        let kneeSOC: Double?
        let kneeIndex: Double
        
        // Стабильность
        let microDropCount: Int
        let stabilityScore: Double // 0-100
        
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
    @Published private(set) var lastResult: QuickHealthResult?
    
    // MARK: - Private Properties
    
    private var samples: [BatteryReading] = []
    private var dcirMeasurements: [DCIRCalculator.DCIRPoint] = []
    private var energyWindowStart: Date?
    private var energyWindowStartIndex: Int = 0
    
    private weak var batteryViewModel: BatteryViewModel?
    private weak var loadGenerator: LoadGenerator?
    private weak var videoLoadEngine: VideoLoadEngine?
    
    private var cancellables = Set<AnyCancellable>()
    private let testTargetSOCs = [80, 60, 40, 20] // Уровни SOC для пульс-тестов
    private var currentTargetIndex = 0
    
    // Настройки теста
    private let calibrationDurationSec: TimeInterval = 150 // 2.5 мин калибровка в покое
    private let pulseDurationSec: TimeInterval = 10 // 10 сек пульс нагрузки
    private let restDurationSec: TimeInterval = 25 // 25 сек отдых между пульсами
    
    // MARK: - Public Methods
    
    /// Привязывает необходимые зависимости
    func bind(
        batteryViewModel: BatteryViewModel,
        loadGenerator: LoadGenerator,
        videoLoadEngine: VideoLoadEngine? = nil
    ) {
        self.batteryViewModel = batteryViewModel
        self.loadGenerator = loadGenerator
        self.videoLoadEngine = videoLoadEngine
        
        // Подписываемся на обновления батареи
        batteryViewModel.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleBatteryUpdate(snapshot)
            }
            .store(in: &cancellables)
    }
    
    /// Запускает быстрый тест здоровья
    func start() {
        guard state == .idle else { return }
        
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
        
        guard !vm.state.isCharging else {
            state = .error(message: "Please disconnect power adapter before starting test")
            return
        }
        
        // Инициализируем тест
        samples.removeAll()
        dcirMeasurements.removeAll()
        currentTargetIndex = 0
        progress = 0.0
        
        state = .calibrating
        currentStep = "Calibrating baseline (2-3 minutes)..."
        
        // Начинаем калибровку в покое
        scheduleStateChange(to: .pulseTesting(targetSOC: testTargetSOCs[0]), after: calibrationDurationSec)
    }
    
    /// Останавливает тест
    func stop() {
        // Останавливаем генераторы нагрузки
        loadGenerator?.stop(reason: .userStopped)
        videoLoadEngine?.stop()
        
        state = .idle
        currentStep = ""
        progress = 0.0
        
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
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
        
        // Обрабатываем состояние теста
        switch state {
        case .calibrating:
            progress = min(0.2, Double(samples.count * 30) / (calibrationDurationSec * 60)) // каждые 30 сек = ~2% прогресса
            
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
            currentStep = "Waiting for battery to reach \(targetSOC)% (current: \(currentSOC)%)"
            return
        }
        
        // Выполняем серию пульс-тестов на этом уровне SOC
        performPulseTests(at: targetSOC) {
            // После завершения пульс-тестов на этом уровне
            self.currentTargetIndex += 1
            
            if self.currentTargetIndex < self.testTargetSOCs.count {
                // Переходим к следующему уровню SOC
                let nextTargetSOC = self.testTargetSOCs[self.currentTargetIndex]
                self.state = .pulseTesting(targetSOC: nextTargetSOC)
                self.progress = 0.3 + Double(self.currentTargetIndex) * 0.15 // 30-75% прогресса
            } else {
                // Все пульс-тесты завершены, переходим к измерению энергетического окна
                self.startEnergyWindowTest()
            }
        }
    }
    
    private func performPulseTests(at socLevel: Int, completion: @escaping () -> Void) {
        currentStep = "Pulse testing at \(socLevel)% SOC"
        
        // Запускаем последовательность: light → medium → heavy → off
        var pulseIndex = 0
        let loadLevels: [LoadLevel] = [.light, .medium, .heavy]
        
        func runNextPulse() {
            guard pulseIndex < loadLevels.count else {
                completion()
                return
            }
            
            let loadLevel = loadLevels[pulseIndex]
            let pulseStartIndex = samples.count - 1
            
            // Включаем нагрузку
            applyLoad(loadLevel)
            
            // Через 10 секунд выключаем нагрузку и измеряем DCIR
            DispatchQueue.main.asyncAfter(deadline: .now() + pulseDurationSec) {
                self.applyLoad(.off)
                
                // Измеряем DCIR
                if let dcirPoint = DCIRCalculator.estimateDCIR(
                    samples: self.samples,
                    pulseStartIndex: pulseStartIndex,
                    windowSeconds: 3.0
                ) {
                    self.dcirMeasurements.append(dcirPoint)
                }
                
                // Отдыхаем 25 секунд перед следующим пульсом
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restDurationSec) {
                    pulseIndex += 1
                    runNextPulse()
                }
            }
        }
        
        runNextPulse()
    }
    
    private func startEnergyWindowTest() {
        state = .energyWindow
        currentStep = "Measuring energy delivery (80→50% SOC)"
        progress = 0.8
        
        energyWindowStart = Date()
        energyWindowStartIndex = samples.count
        
        // Включаем среднюю нагрузку для стабильного потребления
        applyLoad(.medium)
    }
    
    private func handleEnergyWindowState(snapshot: BatterySnapshot) {
        let currentSOC = snapshot.percentage
        
        if currentSOC <= 50 {
            // Достигли 50% SOC, завершаем измерение энергетического окна
            applyLoad(.off)
            progress = 0.9
            
            // Переходим к анализу
            analyzeResults()
        } else {
            currentStep = "Energy window test: \(currentSOC)% → 50%"
        }
    }
    
    private func analyzeResults() {
        state = .analyzing
        currentStep = "Analyzing test results..."
        progress = 0.95
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.performAnalysis()
            
            DispatchQueue.main.async {
                self.lastResult = result
                self.state = .completed(result: result)
                self.currentStep = "Test completed"
                self.progress = 1.0
            }
        }
    }
    
    private func performAnalysis() -> QuickHealthResult {
        let startTime = samples.first?.timestamp ?? Date()
        let endTime = Date()
        let durationMinutes = endTime.timeIntervalSince(startTime) / 60.0
        
        // Анализ энергии 80→50%
        let energyWindowSamples = Array(samples[energyWindowStartIndex...])
        let energyAnalysis = EnergyCalculator.analyzeEnergyPerformance(
            samples: energyWindowSamples,
            designCapacityWh: nil
        )
        
        // Анализ DCIR
        let dcirAnalysis = DCIRCalculator.analyzeDCIR(dcirPoints: dcirMeasurements)
        
        // Анализ OCV
        let ocvAnalyzer = OCVAnalyzer(dcirPoints: dcirMeasurements)
        let ocvAnalysis = ocvAnalyzer.analyzeOCV(from: samples)
        
        // Подсчет микро-дропов
        let microDrops = countMicroDrops(in: samples)
        let stabilityScore = calculateStabilityScore(microDrops: microDrops, samples: samples)
        
        // Композитный скор здоровья (по формуле эксперта)
        let healthScore = calculateCompositeHealthScore(
            sohEnergy: energyAnalysis?.sohEnergy ?? 85.0,
            dcirAt50: dcirAnalysis.dcirAt50Percent,
            dcirAt20: dcirAnalysis.dcirAt20Percent,
            kneeIndex: ocvAnalysis.kneeIndex,
            stabilityScore: stabilityScore
        )
        
        // Рекомендация
        let recommendation = generateRecommendation(healthScore: healthScore)
        
        return QuickHealthResult(
            startedAt: startTime,
            completedAt: endTime,
            durationMinutes: durationMinutes,
            energyDelivered80to50Wh: energyAnalysis?.energyDelivered ?? 0,
            sohEnergy: energyAnalysis?.sohEnergy ?? 85.0,
            averagePower: energyAnalysis?.averagePower ?? 0,
            dcirPoints: dcirMeasurements,
            dcirAt50Percent: dcirAnalysis.dcirAt50Percent,
            dcirAt20Percent: dcirAnalysis.dcirAt20Percent,
            kneeSOC: ocvAnalysis.kneeSOC,
            kneeIndex: ocvAnalysis.kneeIndex,
            microDropCount: microDrops,
            stabilityScore: stabilityScore,
            healthScore: healthScore,
            recommendation: recommendation
        )
    }
    
    private func calculateCompositeHealthScore(
        sohEnergy: Double,
        dcirAt50: Double?,
        dcirAt20: Double?,
        kneeIndex: Double,
        stabilityScore: Double
    ) -> Double {
        // Формула эксперта: 40% SOH_energy + 25% DCIR + 20% колено + 10% стабильность + 5% температура
        
        var score: Double = 0
        
        // 40% - SOH по энергии
        score += 0.4 * sohEnergy
        
        // 25% - DCIR оценка
        var dcirScore: Double = 100
        if let dcir50 = dcirAt50 {
            dcirScore = max(0, 100 - (dcir50 - 100) / 2) // штраф за превышение 100 мОм
        }
        if let dcir20 = dcirAt20 {
            let dcir20Score = max(0, 100 - (dcir20 - 200) / 3) // штраф за превышение 200 мОм
            dcirScore = (dcirScore + dcir20Score) / 2
        }
        score += 0.25 * dcirScore
        
        // 20% - качество колена
        score += 0.2 * kneeIndex
        
        // 10% - стабильность
        score += 0.1 * stabilityScore
        
        // 5% - температурная терпимость (упрощенно)
        score += 0.05 * 100 // пока оптимистично
        
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
            videoLoadEngine?.stop()
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
}