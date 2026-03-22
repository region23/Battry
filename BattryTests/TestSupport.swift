import Foundation
@testable import Battry

func makeReading(
    at timeOffset: TimeInterval,
    percentage: Int,
    voltage: Double = 12.0,
    amperage: Double,
    isCharging: Bool = false,
    powerSource: PowerSource = .battery,
    maxCapacity: Int? = 5000,
    designCapacity: Int? = 6000,
    temperature: Double = 30.0
) -> BatteryReading {
    BatteryReading(
        timestamp: Date(timeIntervalSince1970: timeOffset),
        percentage: percentage,
        isCharging: isCharging,
        powerSource: powerSource,
        voltage: voltage,
        temperature: temperature,
        maxCapacity: maxCapacity,
        designCapacity: designCapacity,
        amperage: amperage
    )
}

