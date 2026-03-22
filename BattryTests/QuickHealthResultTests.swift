import XCTest
@testable import Battry

final class QuickHealthResultTests: XCTestCase {
    func testEnergyWindowComputedPropertiesMarkCompleteWindow() {
        let result = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 65,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15
        )

        XCTAssertEqual(result.energyWindowMeasuredSpanPercent, 15)
        XCTAssertEqual(result.energyWindowDisplayLabel, "80→65%")
        XCTAssertFalse(result.energyEstimateIsProvisional)
    }

    func testEnergyWindowComputedPropertiesMarkPartialWindowAsProvisional() {
        let result = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 70,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15
        )

        XCTAssertEqual(result.energyWindowMeasuredSpanPercent, 10)
        XCTAssertEqual(result.energyWindowDisplayLabel, "80→70%")
        XCTAssertTrue(result.energyEstimateIsProvisional)
    }

    func testLegacyDecodingKeepsBackwardCompatibilityWithoutNewEnergyWindowFields() throws {
        let current = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 65,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(current)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "energyWindowStartPercent")
        payload.removeValue(forKey: "energyWindowEndPercent")
        payload.removeValue(forKey: "energyWindowTargetEndPercent")
        payload.removeValue(forKey: "energyWindowExpectedSpanPercent")
        payload.removeValue(forKey: "sohCapacity")
        payload.removeValue(forKey: "batteryConditionCode")
        payload.removeValue(forKey: "measurementConfidenceCode")

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(QuickHealthTest.QuickHealthResult.self, from: legacyData)

        XCTAssertNil(decoded.energyWindowStartPercent)
        XCTAssertNil(decoded.energyWindowEndPercent)
        XCTAssertNil(decoded.energyWindowTargetEndPercent)
        XCTAssertNil(decoded.energyWindowExpectedSpanPercent)
        XCTAssertEqual(decoded.energyWindowDisplayLabel, "80→65%")
        XCTAssertFalse(decoded.energyEstimateIsProvisional)
        XCTAssertNil(decoded.sohCapacity)
        XCTAssertEqual(decoded.batteryCondition, QuickHealthTest.BatteryCondition.healthy)
        XCTAssertEqual(decoded.measurementConfidence, QuickHealthTest.MeasurementConfidence.high)
    }

    func testDerivedAssessmentMarksReplacementWhenSignalsConverge() {
        let result = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 65,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15,
            sohEnergy: 77,
            sohCapacity: 78,
            dcirAt50Percent: 235,
            unstableUnderLoad: true,
            microDropRatePerHour: 3.2
        )

        XCTAssertEqual(result.batteryCondition, QuickHealthTest.BatteryCondition.replacementRecommended)
        XCTAssertTrue(result.critical)
    }

    func testDerivedAssessmentMarksLowConfidenceForPartialNoisyRun() {
        let result = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 72,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15,
            dcirPoints: [makeDCIRPoint()],
            averageTemperature: 37,
            temperatureQuality: 58,
            powerControlQuality: 68
        )

        XCTAssertEqual(result.measurementConfidence, QuickHealthTest.MeasurementConfidence.low)
        XCTAssertFalse(result.critical)
    }

    func testDeduplicatedResultsKeepSingleEntryPerStartedAt() {
        var base = makeResult(
            energyWindowStartPercent: 80,
            energyWindowEndPercent: 65,
            energyWindowTargetEndPercent: 65,
            energyWindowExpectedSpanPercent: 15
        )
        var withReport = base
        withReport.reportPath = "/tmp/report.html"

        let deduplicated = QuickHealthTest.deduplicatedResults([base, withReport, base])

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated.first?.reportPath, "/tmp/report.html")
    }

    private func makeResult(
        energyWindowStartPercent: Int?,
        energyWindowEndPercent: Int?,
        energyWindowTargetEndPercent: Int?,
        energyWindowExpectedSpanPercent: Int?,
        sohEnergy: Double = 91,
        sohCapacity: Double? = 90,
        dcirPoints: [DCIRCalculator.DCIRPoint] = [],
        dcirAt50Percent: Double? = 140,
        unstableUnderLoad: Bool = false,
        microDropRatePerHour: Double = 0,
        averageTemperature: Double = 29,
        temperatureQuality: Double = 92,
        powerControlQuality: Double = 96
    ) -> QuickHealthTest.QuickHealthResult {
        QuickHealthTest.QuickHealthResult(
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 1800),
            durationMinutes: 30,
            energyDelivered80to50Wh: 8.4,
            sohEnergy: sohEnergy,
            sohCapacity: sohCapacity,
            averagePower: 10,
            targetPower: 10,
            powerPreset: PowerPreset.medium.rawValue,
            energyWindowStartPercent: energyWindowStartPercent,
            energyWindowEndPercent: energyWindowEndPercent,
            energyWindowTargetEndPercent: energyWindowTargetEndPercent,
            energyWindowExpectedSpanPercent: energyWindowExpectedSpanPercent,
            dcirPoints: dcirPoints,
            dcirAt50Percent: dcirAt50Percent,
            dcirAt20Percent: 210,
            kneeSOC: 18,
            kneeIndex: 1.2,
            microDropCount: 0,
            microDropCountAbove20: 0,
            microDropCountBelow20: 0,
            microDropRatePerHour: microDropRatePerHour,
            microDropRateAbove20PerHour: 0,
            microDropRateBelow20PerHour: 0,
            unstableUnderLoad: unstableUnderLoad,
            stabilityScore: 95,
            averageTemperature: averageTemperature,
            normalizedSOH: 90,
            temperatureQuality: temperatureQuality,
            powerControlQuality: powerControlQuality,
            healthScore: 89,
            batteryConditionCode: nil,
            measurementConfidenceCode: nil,
            recommendation: "Looks good"
        )
    }

    private func makeDCIRPoint() -> DCIRCalculator.DCIRPoint {
        DCIRCalculator.DCIRPoint(
            socPercent: 50,
            resistanceMohm: 150,
            timestamp: Date(timeIntervalSince1970: 0),
            quality: 90
        )
    }
}
