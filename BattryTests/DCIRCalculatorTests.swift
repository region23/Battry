import XCTest
@testable import Battry

final class DCIRCalculatorTests: XCTestCase {
    func testEstimateDCIRReturnsExpectedResistanceFromPulseWindow() throws {
        let samples = [
            makeReading(at: 0, percentage: 60, voltage: 12.0, amperage: -500),
            makeReading(at: 1, percentage: 60, voltage: 12.0, amperage: -500),
            makeReading(at: 2, percentage: 60, voltage: 12.0, amperage: -500),
            makeReading(at: 3, percentage: 60, voltage: 12.0, amperage: -500),
            makeReading(at: 4, percentage: 59, voltage: 11.8, amperage: -2500),
            makeReading(at: 5, percentage: 59, voltage: 11.8, amperage: -2500),
        ]

        let point = DCIRCalculator.estimateDCIR(samples: samples, pulseStartIndex: 3, windowSeconds: 2.0)
        let unwrapped = try XCTUnwrap(point)

        XCTAssertEqual(unwrapped.socPercent, 59.5, accuracy: 0.001)
        XCTAssertEqual(unwrapped.resistanceMohm, 100.0, accuracy: 0.001)
        XCTAssertGreaterThan(unwrapped.quality, 0)
    }

    func testAnalyzeDCIRInterpolatesKeySOCPoints() throws {
        let points = [
            DCIRCalculator.DCIRPoint(socPercent: 80, resistanceMohm: 100, timestamp: .distantPast, quality: 90),
            DCIRCalculator.DCIRPoint(socPercent: 20, resistanceMohm: 200, timestamp: .distantPast, quality: 90),
        ]

        let analysis = DCIRCalculator.analyzeDCIR(dcirPoints: points)
        let dcirAt50 = try XCTUnwrap(analysis.dcirAt50Percent)
        let dcirAt20 = try XCTUnwrap(analysis.dcirAt20Percent)

        XCTAssertEqual(analysis.dcirPoints.map(\.socPercent), [80, 20], "Points should stay sorted from high to low SOC")
        XCTAssertEqual(dcirAt50, 150.0, accuracy: 0.001)
        XCTAssertEqual(dcirAt20, 200.0, accuracy: 0.001)
        XCTAssertLessThan(analysis.resistanceTrend, 0.0)
    }
}
