import Foundation
import IOKit.ps
import IOKit

/// Источник питания устройства
enum PowerSource: String {
    case ac, battery, unknown
}

/// Снимок состояния батареи на момент чтения
struct BatterySnapshot: Equatable {
    /// Процент заряда (0–100)
    var percentage: Int = 0
    /// Флаг, что питание подключено и идёт заряд
    var isCharging: Bool = false
    /// Откуда питание: от сети или от батареи
    var powerSource: PowerSource = .unknown
    /// Оценка времени до разряда, мин
    var timeToEmptyMin: Int? = nil
    /// Оценка времени до полной зарядки, мин
    var timeToFullMin: Int? = nil

    // Advanced (from IORegistry if available)
    /// Паспортная ёмкость (mAh)
    var designCapacity: Int = 0
    /// Фактическая максимальная ёмкость (mAh)
    var maxCapacity: Int = 0
    /// Количество циклов заряд/разряд
    var cycleCount: Int = 0
    /// Напряжение (В)
    var voltage: Double = 0
    /// Температура (°C)
    var temperature: Double = 0 // in °C
}

enum BatteryService {
    /// Читает снимок состояния батареи из системных API (IOPS + IORegistry)
    static func read() -> BatterySnapshot {
        var snap = BatterySnapshot()

        // IOPS: надёжно для процентов и статусов
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as Array
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, item).takeUnretainedValue() as? [String: Any] else { continue }

            // Используем IOPS только для процентов, не для mAh
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                snap.percentage = Int((Double(cur) / Double(max)) * 100.0)
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
            // Паспортная ёмкость
            if let dc = dict["DesignCapacity"] as? Int, dc > 0 { snap.designCapacity = dc }
            if snap.designCapacity == 0, let nominal = dict["NominalChargeCapacity"] as? Int, nominal > 0 {
                snap.designCapacity = nominal
            }

            // Фактическая ёмкость в mAh (приоритет: AppleRawMaxCapacity → FullChargeCapacity → NominalChargeCapacity → MaxCapacity (>1000))
            var maxMah: Int = 0
            if let raw = dict["AppleRawMaxCapacity"] as? Int, raw > 0 {
                maxMah = raw
            } else if let fcc = dict["FullChargeCapacity"] as? Int, fcc > 0 {
                maxMah = fcc
            } else if let nominal = dict["NominalChargeCapacity"] as? Int, nominal > 0 {
                maxMah = nominal
            } else if let mc = dict["MaxCapacity"] as? Int, mc > 1000 {
                maxMah = mc
            }
            if maxMah > 0 { snap.maxCapacity = maxMah }

            if let cc = dict["CycleCount"] as? Int { snap.cycleCount = cc }
            if let mv = dict["Voltage"] as? Int { snap.voltage = Double(mv) / 1000.0 } // mV -> V
            if let t = dict["Temperature"] as? Int { snap.temperature = Double(t) / 100.0 } // centi-°C -> °C
        }

        return snap
    }

    /// Проверяет, есть ли у устройства батарея (актуально для Mac mini/Studio)
    static func hasBattery() -> Bool {
        // Надёжный способ: проверяем наличие AppleSmartBattery в IORegistry
        if copySmartBatteryProperties() != nil { return true }
        // На всякий случай дублируем проверку по IOPS только для internal battery
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as Array
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, item).takeUnretainedValue() as? [String: Any] else { continue }
            if let psType = desc[kIOPSTypeKey] as? String, psType == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }

    /// Достаёт свойства из AppleSmartBattery в IORegistry
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
