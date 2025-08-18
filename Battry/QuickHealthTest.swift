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
    @Published private(set) var lastResult: QuickHealthResult?
    
    // MARK: - Private Properties
    
    private var samples: [BatteryReading] = []
    private var dcirMeasurements: [DCIRCalculator.DCIRPoint] = []
    private var energyWindowStart: Date?
    private var energyWindowStartIndex: Int = 0
    
    private weak var batteryViewModel: BatteryViewModel?
    private weak var loadGenerator: LoadGenerator?
    // Video load removed
    
    // Constant Power контроль
    private lazy var constantPowerController = ConstantPowerController()
    private var selectedPowerPreset: PowerPreset = .medium
    private var targetPowerW: Double = 10.0
    
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
        loadGenerator: LoadGenerator
    ) {
        self.batteryViewModel = batteryViewModel
        self.loadGenerator = loadGenerator
        
        // Настраиваем ConstantPowerController
        setupConstantPowerController()
        
        // Подписываемся на обновления батареи
        batteryViewModel.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleBatteryUpdate(snapshot)
            }
            .store(in: &cancellables)
    }
    
    /// Устанавливает пресет мощности для теста
    func setPowerPreset(_ preset: PowerPreset) {
        guard state == .idle else { return }
        selectedPowerPreset = preset
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
        
        state = .calibrating
        currentStep = "Calibrating baseline (2-3 minutes)..."
        
        // Начинаем калибровку в покое
        scheduleStateChange(to: .pulseTesting(targetSOC: testTargetSOCs[0]), after: calibrationDurationSec)
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
        currentStep = "Measuring energy delivery (80→50% SOC) at \(String(format: "%.1f", targetPowerW))W"
        progress = 0.8
        
        energyWindowStart = Date()
        energyWindowStartIndex = samples.count
        
        // Запускаем Constant Power контроллер для стабильного потребления
        constantPowerController.start(targetPower: targetPowerW)
    }
    
    private func handleEnergyWindowState(snapshot: BatterySnapshot) {
        let currentSOC = snapshot.percentage
        
        if currentSOC <= 50 {
            // Достигли 50% SOC, завершаем измерение энергетического окна
            constantPowerController.stop()
            progress = 0.9
            
            // Переходим к анализу
            analyzeResults()
        } else {
            currentStep = "Energy window test: \(currentSOC)% → 50% | \(String(format: "%.1f", constantPowerController.currentPowerW))W"
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
        
        // Температурный анализ
        let temperatures = samples.map(\.temperature)
        let avgTemperature = temperatures.reduce(0, +) / Double(max(1, temperatures.count))
        let tempQuality = TemperatureNormalizer.temperatureQuality(avgTemperature)
        
        // Температурная нормализация
        let tempNormalization = TemperatureNormalizer.normalize(
            sohEnergy: energyAnalysis?.sohEnergy ?? 85.0,
            dcirAt50: dcirAnalysis.dcirAt50Percent,
            averageTemperature: avgTemperature
        )
        
        // Композитный скор здоровья (по формуле эксперта)
        let healthScore = calculateCompositeHealthScore(
            sohEnergy: tempNormalization.normalizedSOH,
            dcirAt50: tempNormalization.normalizedDCIR,
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
            targetPower: targetPowerW,
            powerPreset: selectedPowerPreset.rawValue,
            dcirPoints: dcirMeasurements,
            dcirAt50Percent: dcirAnalysis.dcirAt50Percent,
            dcirAt20Percent: dcirAnalysis.dcirAt20Percent,
            kneeSOC: ocvAnalysis.kneeSOC,
            kneeIndex: ocvAnalysis.kneeIndex,
            microDropCount: microDrops,
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
                // Управляем нагрузкой через LoadGenerator
                guard let self = self else { return }
                self.applyLoadWithDutyCycle(dutyCycle)
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
}