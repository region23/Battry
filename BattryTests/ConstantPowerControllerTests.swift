import XCTest
@testable import Battry

final class ConstantPowerControllerTests: XCTestCase {
    func testInactiveControllerHasNoRecommendedLoad() async {
        await MainActor.run {
            let controller = ConstantPowerController()

            XCTAssertNil(controller.getRecommendedLoadIntensity())
            XCTAssertFalse(controller.isActive)
            XCTAssertEqual(controller.stateDescription, "Inactive")
        }
    }

    func testStopResetsStateAndTurnsOffLoad() async {
        await MainActor.run {
            let controller = ConstantPowerController()
            var appliedLoads: [Double] = []

            controller.setCallbacks(
                powerReading: { 8 },
                loadControl: { appliedLoads.append($0) }
            )

            controller.start(targetPower: 10)
            controller.stop()

            XCTAssertEqual(appliedLoads.last ?? -1, 0.0, accuracy: 0.0001)
            XCTAssertEqual(controller.targetPowerW, 0.0, accuracy: 0.0001)
            XCTAssertEqual(controller.currentPowerW, 0.0, accuracy: 0.0001)
            XCTAssertEqual(controller.dutyCycle, 0.5, accuracy: 0.0001)
            XCTAssertFalse(controller.isActive)
            if case .idle = controller.state {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected controller to return to idle after stop")
            }
        }
    }
}
