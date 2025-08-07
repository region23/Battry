import Foundation
import IOKit.ps
import IOKit

enum PowerSource: String {
    case ac, battery, unknown
}

struct BatterySnapshot: Equatable {
    var percentage: Int = 0
    var isCharging: Bool = false
    var powerSource: PowerSource = .unknown
    var timeToEmptyMin: Int? = nil
    var timeToFullMin: Int? = nil

    // Advanced (from IORegistry if available)
    var designCapacity: Int = 0
    var maxCapacity: Int = 0
    var cycleCount: Int = 0
    var voltage: Double = 0
    var temperature: Double = 0 // in °C
}

enum BatteryService {
    static func read() -> BatterySnapshot {
        var snap = BatterySnapshot()

        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as Array
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, item).takeUnretainedValue() as? [String: Any] else { continue }

            if let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                snap.percentage = Int((Double(cur) / Double(max)) * 100.0)
                snap.maxCapacity = max // fallback if registry not available
            }
            if let charging = desc[kIOPSIsChargingKey] as? Bool { snap.isCharging = charging }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                snap.powerSource = state == kIOPSACPowerValue ? .ac : (state == kIOPSBatteryPowerValue ? .battery : .unknown)
            }
            if let tte = desc[kIOPSTimeToEmptyKey] as? Int, tte > 0 { snap.timeToEmptyMin = tte }
            if let ttf = desc[kIOPSTimeToFullChargeKey] as? Int, ttf > 0 { snap.timeToFullMin = ttf }
        }

        // Enrich from IORegistry (AppleSmartBattery)
        if let dict = copySmartBatteryProperties() {
            if let dc = dict["DesignCapacity"] as? Int { snap.designCapacity = dc }
            if let mc = dict["MaxCapacity"] as? Int { snap.maxCapacity = mc }
            if let cc = dict["CycleCount"] as? Int { snap.cycleCount = cc }
            if let mv = dict["Voltage"] as? Int { snap.voltage = Double(mv) / 1000.0 } // mV -> V
            if let t = dict["Temperature"] as? Int { snap.temperature = Double(t) / 100.0 } // centi-°C -> °C
        }

        return snap
    }

    static func hasBattery() -> Bool {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as Array
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, item).takeUnretainedValue() as? [String: Any] else { continue }
            
            if let transportType = desc[kIOPSTransportTypeKey] as? String {
                // Если есть транспортный тип батареи, значит батарея присутствует
                if transportType == kIOPSInternalBatteryType || transportType == kIOPSUSBTransportType || transportType == kIOPSNetworkTransportType {
                    return true
                }
            }
            
            if let psType = desc[kIOPSTypeKey] as? String {
                // Проверяем тип источника питания
                if psType == kIOPSInternalBatteryType {
                    return true
                }
            }
        }
        return false
    }

    private static func copySmartBatteryProperties() -> [String: Any]? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service == 0 { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>? = nil
        let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }
}
