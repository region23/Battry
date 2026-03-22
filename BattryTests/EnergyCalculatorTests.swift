import XCTest
@testable import Battry

final class EnergyCalculatorTests: XCTestCase {
    func testIntegrateEnergyUsesTrapezoidalRuleForDischargeSamples() {
        let samples = [
            makeReading(at: 0, percentage: 80, amperage: -1000),
            makeReading(at: 3600, percentage: 60, amperage: -1000),
        ]

        let energyWh = EnergyCalculator.integrateEnergy(samples: samples)

        XCTAssertEqual(energyWh, 12.0, accuracy: 0.001)
    }

    func testIntegrateEnergyIgnoresChargingIntervals() {
        let samples = [
            makeReading(at: 0, percentage: 60, amperage: 1200, isCharging: true, powerSource: .ac),
            makeReading(at: 1800, percentage: 65, amperage: 1200, isCharging: true, powerSource: .ac),
        ]

        let energyWh = EnergyCalculator.integrateEnergy(samples: samples)

        XCTAssertEqual(energyWh, 0.0, accuracy: 0.001)
    }

    func testAnalyzeEnergyPerformanceScalesMeasuredWindowToEstimatedFullSOH() throws {
        let samples = [
            makeReading(at: 0, percentage: 80, amperage: -1000),
            makeReading(at: 3600, percentage: 60, amperage: -1000),
        ]

        let analysis = EnergyCalculator.analyzeEnergyPerformance(samples: samples, designCapacityWh: 60.0)
        let unwrapped = try XCTUnwrap(analysis)

        XCTAssertEqual(unwrapped.energyDelivered, 12.0, accuracy: 0.001)
        XCTAssertEqual(unwrapped.averagePower, 12.0, accuracy: 0.001)
        XCTAssertEqual(unwrapped.durationHours, 1.0, accuracy: 0.001)
        XCTAssertEqual(unwrapped.sohEnergy, 100.0, accuracy: 0.001)
    }
}
