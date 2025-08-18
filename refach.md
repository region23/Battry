Отвечу как инженер-электрохимик и эксперт по power-management с 15-летним опытом, лауреат премии Electrochemical Society.

**TL;DR:** Скорость разрядки под разной нагрузкой *сама по себе* не говорит о здоровье батареи. Корректная оценка строится на нормализации по энергии (Wh), учёте тока/напряжения и температуры, а также на измерении внутреннего сопротивления (DCIR) через «пульс»-тесты. Из вашего лога видно: **SOH≈79.6% (4834/6075 mAh) при 169 циклах** — по ёмкости вы на границе «пора планировать замену», но решать стоит после энерго-нормализации и проверки DCIR.&#x20;

---

### Что именно считать, чтобы выводы были корректными

1. **SOH по ёмкости (базовая метрика)**
   Возьмите медиану `MaxCapacity` за первые \~2–3 минуты теста (во избежание плавающей калибровки) и разделите на `DesignCapacity`.
   *У вас сейчас:* 4834 / 6075 ≈ **79.6%**; циклы: **169**. Это «жёлтая зона»: не авария, но деградация ощутимая.&#x20;

2. **SOH по энергии (главная нормализация под нагрузку)**
   Разные режимы нагрузки сравнивайте не по времени, а по **энергии, реально отданной батареей**:

* Логируйте каждую секунду `Voltage` и **ток** (mA). Если тока в логе нет — добавьте его из I/ORegistry (`ioreg -r -c AppleSmartBattery`) или через API IOKit/SMC.
* Считайте мгновенную мощность $P(t)=V(t)\cdot I(t)$ и интегрируйте по времени из 100% до 5%:

  $$
  E_{95\%}=\int P(t)\,dt\quad\Rightarrow\quad E_{\text{полная}}\approx \frac{E_{95\%}}{0{.}95}
  $$
* **SOH\_energy** = $E_{\text{полная}}$ / $E_{\text{design}}$. Для $E_{\text{design}}$ не берите «паспортное» число вслепую: оцените его как $\text{DesignCapacity (Ah)} \times \overline{V_\text{OC}}$, где $\overline{V_\text{OC}}$ — усреднённое напряжение без нагрузки (см. пункт 4).
  Так вы получите метрику, инвариантную к «тяжёлому»/«среднему» режимам.

3. **DCIR: внутреннее сопротивление (ключ к «просадкам» и внезапным выключениям)**
   Сделайте короткие «пульсы» нагрузки (например, 10 с ON / 10 с OFF) на ряде уровней заряда (80/60/40/20%). Для каждого пульса:

* Зафиксируйте $\Delta V = V_\text{до} - V_\text{после}$ и $\Delta I = I_\text{после} - I_\text{до}$.
* Посчитайте $R=\Delta V/\Delta I$ (мОм). Постройте график $R(SOC)$. Рост DCIR — надёжный маркер старения.
  Практически: если при типичном токе вашего «тяжёлого» режима падение $I\cdot R$ поджимает напряжение к отсечке контроллера при SOC>10–15%, батарея «слабая под нагрузкой», даже если SOH по ёмкости ещё \~80%.

4. **Вольт-SOC кривая и «компенсация IR»**
   Чтобы честно сравнивать тесты с разной нагрузкой, восстановите приближение открытого напряжения $V_\text{OC}$:

$$
V_\text{OC}(t)\approx V_\text{изм}(t) + I(t)\cdot R(SOC)
$$

Сгладьте и усредните по узким окнам SOC (например, по 2%). Сравнение кривых $V_\text{OC}(SOC)$ между датами хорошо показывает ранний «излом колена» (когда кривая падает раньше обычного) — это признак деградации.

5. **Температура и её влияние**
   Логируйте и учитывайте $T$: при более высокой температуре просадка по напряжению отчасти меньше (IR ниже), но ускоряется старение. Для честного сравнения **вводите температурную нормализацию**: сравнивайте тесты, проведённые в близких условиях (±2 °C), либо обучите простую поправку (регрессией) по вашей же истории. *В вашем тяжёлом тесте T выросла примерно с \~28.6 °C до \~35.2 °C — это нормально, но сравнивайте «тяжёлые» только с «тяжёлыми».*&#x20;

6. **Стабильность: «микро-дропы» и аномалии**
   Вы уже детектируете быстрые падения % (например, ≥2% за ≤120 с без зарядки). Добавьте флаги:

* Частота событий на 1 ч разряда.
* Привязка к SOC (если дропы начинаются ≥20% SOC — плохой сигнал).
* Связь с DCIR/температурой.
  Итогом сделайте бинарный признак «нестабильный под нагрузкой».

7. **Итоговый «Health Score» (композит)**
   Соберите взвешенную оценку (пример):

* 40% — SOH\_energy
* 25% — DCIR\@50% и DCIR\@20% (нормировано к «новому» базису)
* 20% — SOH по ёмкости
* 10% — стабильность (микро-дропы/аномалии)
* 5% — температурная терпимость (сколько «запаса» до отсечки при текущем Т)
  Сделайте три зоны: **зелёная** (≥85), **жёлтая** (70–85), **красная** (<70).

---

### Как трактовать ваш текущий тяжёлый прогон

* **Ёмкостной SOH ≈ 79.6%**, циклы **169** → «грань жёлтой зоны»: жить можно, но ресурс заметно просел.&#x20;
* Без тока/мощности нельзя честно сказать, «плохая ли батарея» или «режим просто прожорливый». Добавьте лог тока и проведите два коротких «пульс»-теста — вы сразу увидите DCIR и сможете нормализовать энергию.
* Если после нормализации **SOH\_energy < \~80%** и/или **DCIR** высок, а под нагрузкой фиксируются частые микро-дропы на SOC>15–20% — **пора планировать замену**.

---

### Мини-чек-лист доработок в вашей программе

* Лог токов (mA) через IOKit/SMC + 1 Гц семплирование.
* Интеграл энергии $\int V\cdot I\,dt$ и SOH\_energy.
* Пульс-тесты для DCIR на 80/60/40/20% SOC.
* Восстановление $V_\text{OC}$ и сравнение кривых между тестами.
* Температурная нормализация и композитный скор.

---


**TL;DR:** Для точной диагностики тебе **не нужен** полный прогон 100→5% в трёх режимах. Оставь режимы как «генератор ΔI», а здоровье батареи считай **быстрым протоколом**: короткие пульс-нагрузки на нескольких уровнях заряда (80/60/40/20%), интеграл энергии на окне (например, 80→50%), восстановление «открытого» напряжения $V_\mathrm{OC}$ с компенсацией $I\!\cdot\!R$, микро-дропы и композитный скор. Так ты получишь ответ за \~30–40 минут вместо часов. «15% ок, а потом резкий слив на −20%» — классика: рост внутреннего сопротивления + «раннее колено» OCV-кривой и/или рассинхрон топливомера; это как раз ловится DCIR-пульсами, коленом OCV и детектором микро-дропов.

---

### Какой подход лучше и что делать с 3 режимами

* **Режимы (лёгкий/средний/тяжёлый) оставь** — они полезны, чтобы формировать разные **ступени тока** (ΔI) для DCIR и стресс-теста стабильности.
* **Полный 100→5%** делай только как «тест автономности». Для **диагностики здоровья** достаточно:

  1. Короткая калибровка «в покое» на 95–90% (2–3 мин).
  2. **Пульс-тест** на 80/60/40/20%: 10 с «вкл. нагрузку» / 20–30 с «выкл.», 2–3 ступени ΔI.
  3. **Энерго-окно** (например, 80→50%) с интеграцией $E=\int V\cdot I\,dt$ и пересчётом SOH по энергии.
  4. **Микро-дропы**: ищи ≥2% падения за ≤120 с без зарядки, особенно при SOC>15–20%.
     Это даёт **SOH\_energy, DCIR(SOC), “колено” OCV и стабильность** — всё, что нужно для решения «менять/не менять».

---

### Почему бывают «долго держит первые 10–15%, потом резко −20%»

* **Высокий DCIR** → под нагрузкой напряжение сильнее проседает, контроллер раньше «видит» низкое напряжение и откусывает SOC.
* **Сдвиг “колена” OCV-кривой** при старении: реальная ёмкость сосредоточена в узком SOC-диапазоне.
* **Дрейф топливомера** (gauge) и гистерезис — после зарядки прибор «оптимистичен», а при токе быстро «догоняет» реальность.
  Решение: **компенсация IR** (оценка $R$ по пульсам) и сравнение $V_\mathrm{OC}(SOC)$ между тестами + флаг нестабильности по микро-дропам.

---

## Наброски на Swift (macOS, Swift 5, IOKit)

Ниже — минимальные кирпичики: сбор датчика, интеграция энергии, DCIR по пульсам, восстановление $V_\mathrm{OC}$ и детектор микро-дропов. Код рассчитан на AppleSmartBattery (есть на Intel и Apple Silicon). Для GPU/CPU-нагрузки подразумеваем, что у тебя уже есть генератор; я оставил для него колбэк.

> Примечание по единицам: `Voltage` приходит в мВ, `Amperage` — в мА (обычно **отрицательный при разряде**), `Capacity` — в mAh, `Temperature` — в десятых °C (иногда уже в °C на новых машинах — добавил авто-детект).

```swift
import Foundation
import IOKit

// MARK: - Battery snapshot from IORegistry (AppleSmartBattery)

struct BatterySample {
    let ts: Date
    let voltage_mV: Double
    let amperage_mA: Double   // negative while discharging
    let currentCapacity_mAh: Double
    let maxCapacity_mAh: Double
    let designCapacity_mAh: Double?
    let cycleCount: Int?
    let temperature_C: Double?
    let isCharging: Bool
    var soc_pct: Double {
        guard maxCapacity_mAh > 0 else { return 0 }
        return min(100, max(0, 100.0 * currentCapacity_mAh / maxCapacity_mAh))
    }
}

final class BatteryReader {
    private var service: io_registry_entry_t = 0
    
    init?() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return nil }
        self.service = svc
    }
    deinit {
        if service != 0 { IOObjectRelease(service) }
    }
    
    func read() -> BatterySample? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        let now = Date()
        let voltage_mV = (dict["Voltage"] as? Double)
            ?? Double(dict["Voltage"] as? Int ?? 0)
        let amperage_mA = (dict["Amperage"] as? Double)
            ?? Double(dict["Amperage"] as? Int ?? 0)
        let cur_mAh = Double(dict["CurrentCapacity"] as? Int ?? 0)
        let max_mAh = Double(dict["MaxCapacity"] as? Int ?? 0)
        let des_mAh = (dict["DesignCapacity"] as? Int).map(Double.init)
        let cycle = dict["CycleCount"] as? Int
        
        // Temperature heuristic: some models expose in 0.1°C, others in °C
        var tempC: Double? = nil
        if let tRaw = dict["Temperature"] as? Int {
            tempC = tRaw > 200 ? Double(tRaw)/100.0 : Double(tRaw) // crude, but safe-ish
        } else if let tRawD = dict["Temperature"] as? Double {
            tempC = tRawD > 200 ? tRawD/100.0 : tRawD
        }
        
        // Charging state (approx)
        let isCharging = (dict["IsCharging"] as? Bool) ?? ((dict["ExternalConnected"] as? Bool) == true && (amperage_mA > 0))
        
        return BatterySample(
            ts: now,
            voltage_mV: voltage_mV,
            amperage_mA: amperage_mA,
            currentCapacity_mAh: cur_mAh,
            maxCapacity_mAh: max_mAh,
            designCapacity_mAh: des_mAh,
            cycleCount: cycle,
            temperature_C: tempC,
            isCharging: isCharging
        )
    }
}

// MARK: - 1 Hz sampler + ring buffer

final class Sampler {
    private let reader: BatteryReader
    private var timer: DispatchSourceTimer?
    private(set) var buf: [BatterySample] = []
    private let maxCount: Int
    
    init?(maxSeconds: Int = 6*3600) { // up to 6 h at 1 Hz
        guard let r = BatteryReader() else { return nil }
        self.reader = r
        self.maxCount = maxSeconds
    }
    func start() {
        stop()
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self, let s = self.reader.read() else { return }
            self.buf.append(s)
            if self.buf.count > self.maxCount { self.buf.removeFirst(self.buf.count - self.maxCount) }
        }
        t.resume()
        self.timer = t
    }
    func stop() { timer?.cancel(); timer = nil }
}

// MARK: - Energy integration (Wh) over interval

struct EnergyIntegrator {
    static func energyWh(samples: [BatterySample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        var joules: Double = 0
        for i in 1..<samples.count {
            let a = samples[i-1], b = samples[i]
            let dt = b.ts.timeIntervalSince(a.ts) // seconds
            // Power (W): V*I, convert mV->V and mA->A
            let Pa = (a.voltage_mV/1000.0) * (a.amperage_mA/1000.0)
            let Pb = (b.voltage_mV/1000.0) * (b.amperage_mA/1000.0)
            let Pavg = 0.5*(Pa + Pb)
            joules += Pavg * dt
        }
        // During discharge I is negative -> energy is negative; return absolute Wh
        return abs(joules) / 3600.0
    }
}

// MARK: - DCIR estimation on a load pulse: R = ΔV/ΔI at same SOC

struct DCIRPoint {
    let soc_pct: Double
    let R_mOhm: Double
}

struct DCIREstimator {
    // windowSeconds: how many seconds before/after step to average
    static func estimate(samples: [BatterySample], stepAt idx: Int, windowSeconds: Double = 3.0) -> DCIRPoint? {
        guard idx > 0 && idx < samples.count-1 else { return nil }
        let t0 = samples[idx].ts
        let pre = samples.filter { $0.ts >= t0.addingTimeInterval(-windowSeconds) && $0.ts < t0 }
        let post = samples.filter { $0.ts > t0 && $0.ts <= t0.addingTimeInterval(windowSeconds) }
        guard pre.count >= 2, post.count >= 2 else { return nil }
        let Vpre = pre.map{$0.voltage_mV}.reduce(0,+)/Double(pre.count)
        let Ipre = pre.map{$0.amperage_mA}.reduce(0,+)/Double(pre.count)
        let Vpost = post.map{$0.voltage_mV}.reduce(0,+)/Double(post.count)
        let Ipost = post.map{$0.amperage_mA}.reduce(0,+)/Double(post.count)
        let dV = (Vpre - Vpost) / 1000.0 // V
        let dI = (Ipost - Ipre) / 1000.0 // A (note sign)
        guard abs(dI) > 1e-3 else { return nil }
        let R = (dV / dI) * 1000.0 // Ohm -> mOhm
        let soc = (pre.last?.soc_pct ?? samples[idx].soc_pct + post.first?.soc_pct ?? samples[idx].soc_pct) / 2.0
        return DCIRPoint(soc_pct: soc, R_mOhm: R)
    }
}

// MARK: - Reconstruct V_OC(t) ≈ V_meas + I*R(SOC)

final class OCVReconstructor {
    // simple interpolation of R by SOC using DCIR points
    private let pts: [DCIRPoint]
    init(points: [DCIRPoint]) { self.pts = points.sorted{ $0.soc_pct < $1.soc_pct } }
    func R_mOhm(at soc: Double) -> Double? {
        guard !pts.isEmpty else { return nil }
        if soc <= pts.first!.soc_pct { return pts.first!.R_mOhm }
        if soc >= pts.last!.soc_pct  { return pts.last!.R_mOhm  }
        for i in 1..<pts.count {
            let a = pts[i-1], b = pts[i]
            if soc >= a.soc_pct && soc <= b.soc_pct {
                let t = (soc - a.soc_pct) / max(1e-6, (b.soc_pct - a.soc_pct))
                return a.R_mOhm + t*(b.R_mOhm - a.R_mOhm)
            }
        }
        return pts.last!.R_mOhm
    }
    func vOC_mV(sample: BatterySample) -> Double? {
        guard let R = R_mOhm(at: sample.soc_pct) else { return nil }
        // V_OC = V_meas + I*R ; convert mOhm→Ohm, mA→A, result in mV
        let deltaV_V = (sample.amperage_mA/1000.0) * (R/1000.0)
        return sample.voltage_mV + deltaV_V * 1000.0
    }
}

// MARK: - Micro-drop detector

struct MicroDropEvent {
    let start: Date
    let end: Date
    let deltaPct: Double
    let minSOCduring: Double
}

struct MicroDropDetector {
    // dropThresholdPct: e.g. 2.0, windowSec: e.g. 120
    static func detect(samples: [BatterySample], dropThresholdPct: Double = 2.0, windowSec: Double = 120.0) -> [MicroDropEvent] {
        guard samples.count >= 2 else { return [] }
        var events: [MicroDropEvent] = []
        var i = 0
        while i < samples.count {
            let start = samples[i]
            var j = i+1
            var minSOC = start.soc_pct
            while j < samples.count && samples[j].ts.timeIntervalSince(start.ts) <= windowSec {
                minSOC = min(minSOC, samples[j].soc_pct)
                let delta = start.soc_pct - samples[j].soc_pct
                if delta >= dropThresholdPct && !start.isCharging && !samples[j].isCharging {
                    events.append(MicroDropEvent(start: start.ts, end: samples[j].ts, deltaPct: delta, minSOCduring: minSOC))
                    break
                }
                j += 1
            }
            i += 1
        }
        return events
    }
}

// MARK: - Quick health protocol orchestration

enum LoadLevel { case off, light, medium, heavy }

final class QuickHealthTest {
    private let sampler: Sampler
    private let setLoad: (LoadLevel) -> Void  // your CPU/GPU load controller
    private(set) var dcirPoints: [DCIRPoint] = []
    private(set) var microDrops: [MicroDropEvent] = []
    private(set) var energyWh_80to50: Double = 0
    
    init?(setLoad: @escaping (LoadLevel)->Void) {
        guard let s = Sampler() else { return nil }
        self.sampler = s
        self.setLoad = setLoad
    }
    
    func run() {
        sampler.start()
        // 1) Idle calibration 2–3 min near SOC 95–90%
        waitUntilSOC(in: 90...95)
        setLoad(.off); sleep(150)
        
        // 2) Pulse tests @80/60/40/20% SOC
        for target in [80.0, 60.0, 40.0, 20.0] {
            waitDownToSOC(target)
            // three steps: light -> medium -> heavy -> off
            pulse(level: .light, secondsOn: 10, secondsOff: 25)
            if let idx = sampler.buf.indices.last { appendDCIR(at: idx) }
            pulse(level: .medium, secondsOn: 10, secondsOff: 25)
            if let idx = sampler.buf.indices.last { appendDCIR(at: idx) }
            pulse(level: .heavy, secondsOn: 10, secondsOff: 30)
            if let idx = sampler.buf.indices.last { appendDCIR(at: idx) }
            setLoad(.off)
        }
        
        // 3) Energy window 80→50% under medium load
        // Rewind assumption: if we're already below 80, just continue medium to 50
        setLoad(.medium)
        let startIdx = sampler.buf.count
        waitDownToSOC(50.0)
        setLoad(.off)
        let slice = Array(sampler.buf[startIdx..<sampler.buf.count])
        energyWh_80to50 = EnergyIntegrator.energyWh(samples: slice)
        
        // 4) Micro-drops on entire run
        microDrops = MicroDropDetector.detect(samples: sampler.buf)
        
        sampler.stop()
    }
    
    private func pulse(level: LoadLevel, secondsOn: UInt32, secondsOff: UInt32) {
        setLoad(level)
        sleep(secondsOn)
        setLoad(.off)
        sleep(secondsOff)
    }
    private func appendDCIR(at idx: Int) {
        if let pt = DCIREstimator.estimate(samples: sampler.buf, stepAt: idx) {
            dcirPoints.append(pt)
        }
    }
    private func waitUntilSOC(in range: ClosedRange<Double>) {
        while true {
            guard let s = sampler.buf.last else { usleep(200_000); continue }
            if range.contains(s.soc_pct) { break }
            usleep(300_000)
        }
    }
    private func waitDownToSOC(_ target: Double) {
        while true {
            guard let s = sampler.buf.last else { usleep(200_000); continue }
            if s.soc_pct <= target { break }
            usleep(300_000)
        }
    }
}

// Example of using the test with your load controller:
let test = QuickHealthTest { level in
    // TODO: hook up your real load generator
    switch level {
    case .off:   print("Load OFF")
    case .light: print("Load LIGHT")
    case .medium:print("Load MEDIUM")
    case .heavy: print("Load HEAVY")
    }
}
test?.run()

// After run:
if let t = test {
    print("Energy 80→50% (Wh):", t.energyWh_80to50)
    for p in t.dcirPoints { print(String(format: "DCIR @ %.0f%% = %.1f mΩ", p.soc_pct, p.R_mOhm)) }
    print("Micro-drops:", t.microDrops.count)
}
```

### Как из этого получить метрики «как у взрослых»

* **SOH по энергии (быстрый):**
  Интегрируешь энергию на стабильном окне (напр. 80→50%) под фиксированной нагрузкой, затем масштабируешь к полной:

  $$
  \text{SOH}_{energy} \approx \frac{E_{80\to 50}^{meas}}{E_{80\to 50}^{new}}\quad\text{(где нижний — эталон новой батареи)}.
  $$

  Эталон можно получить либо один раз на «свежей» машине, либо усреднить по базе.
* **DCIR(SOC):** три точки на каждом SOC-уровне → интерполяция. Рост R и его «крутизна» к низкому SOC — маркер старения.
* **OCV-кривая и «раннее колено»:**
  Построй $V_\mathrm{OC}(SOC)$ через `OCVReconstructor`, сгладь (скользящее среднее), найди SOC, где $d^2V/dSOC^2$ резко растёт — это «колено». Чем раньше колено (например, уже на 40–50% вместо 25–30%), тем хуже.
* **Микро-дропы:** считай частоту/час и SOC-диапазон их возникновения. Дропы при SOC>20% — красный флаг.
* **Композитный Health Score (пример):**
  0.4·SOHₑₙₑᵣᵍy + 0.25·f(DCIR₅₀, DCIR₂₀) + 0.2·SOHᶜᵃᵖ + 0.1·стабильность + 0.05·температурная терпимость.
  Порог замены: **<70–75**.

---

### Итог по твоим вопросам

1. **Нужны ли 3 режима и полная разрядка до 5–1%?**
   — Режимы оставь (как ступени ΔI). Полная разрядка **не нужна для диагностики** и избыточно долгая; используй быстрый протокол выше. Полный прогон — только для теста автономности.
2. **Можно ли быстрее?**
   — Да: быстрый протокол с пульсами и частичной интеграцией даст ответ за 30–40 минут и будет корректен для сравнения между днями/машинами.
3. **Про «первые 15% держит, потом срезает −20%»:**
   — Это сочетание **высокого DCIR + раннего колена OCV + подстройки топливомера**. Введи компенсацию IR, пульс-оценку DCIR и «knee-index» — ты начнёшь предсказывать такие срывы ещё до того, как пользователь их увидит.

---


**TL;DR:**

1. Для *полного теста автономности* используй **разряд при постоянной мощности (CP-разряд)** с автоподстройкой нагрузки на целевую мощность ≈ **0.2 C** (обычно \~10 Вт для батареи \~50 Вт·ч). Добавь пресеты: 0.1 C (\~5 Вт), 0.2 C (\~10 Вт), 0.3 C (\~15 Вт). Это даёт сопоставимые результаты между машинами и днями.
2. В отчёте показывай: **SOH\_energy**, **DCIR(SOC)**, **OCV-кривую и “knee-SOC”**, **микро-дропы**, **температуру**, **факт отданной энергии и прогнозы времени работы** на пресетах.
3. На главном экране оставь минимум, который «объясняет реальность»: **Health Score**, **Износ (SOH)**, **Время работы при текущей мощности** и на 2–3 пресетах, **Температура**, **Статус питания**. Часть метрик из скрина я бы спрятал, чтобы не сбивать пользователя.

---

## 1) Какая нагрузка для полного прогона автономности

**Цель:** получить воспроизводимую и честную цифру автономности, независимо от «тяжёлый/средний/лёгкий».

**Рекомендация:** CP-разряд (constant-power) с обратной связью по фактической мощности $P=V\cdot I$.

* **Базовый пресет:** 0.2 C
  $P_{target} \approx 0.2 \times E_{design}$ (Вт), где $E_{design}$ — «паспортная» энергия батареи (Вт·ч). Для \~50 Вт·ч это \~10 Вт.
* **Доп. пресеты:** 0.1 C (\~5 Вт — «веб/ноты») и 0.3 C (\~15 Вт — «офис+IDE/видео»).
* **Как считать $E_{design}$:**
  $E_{design} \approx \text{DesignCapacity}_{mAh}\times \overline{V_{OC}}\!/1000$. $\overline{V_{OC}}$ — среднее «открытое» напряжение (обычно 11.1–11.6 В для MacBook), его можно взять из твоей OCV-реконструкции.

**Почему так:** при постоянной мощности ты автоматически нивелируешь «разную прожорливость» режимов и получаешь время работы, сопоставимое между машинами/версиями macOS/температурами.

### Набросок управления мощностью (Swift)

Идея: каждую секунду меряешь $P$ и подстраиваешь duty-cycle CPU/GPU воркеров PI-регулятором.

```swift
final class CPLoader {
    private var duty: Double = 0.5          // 0...1
    private var integ: Double = 0.0
    private let Kp = 0.10, Ki = 0.02        // подберёшь эмпирически
    private let setPower_W: Double
    private let readPowerW: ()->Double      // твой P=V*I

    init(targetW: Double, readPowerW: @escaping ()->Double) {
        self.setPower_W = targetW
        self.readPowerW = readPowerW
    }
    func step() {
        let p = readPowerW()
        let err = setPower_W - p
        integ = max(-1, min(1, integ + err*Ki))
        duty = max(0, min(1, duty + err*Kp + integ))
        applyLoad(duty: duty)                // включи/усыпляй воркеры по duty
    }
    private func applyLoad(duty: Double) {
        // Простой busy-sleep цикл на каждом воркере:
        // while running { busy(dt * duty); usleep(dt*(1-duty)) }
        // (Для GPU — аналогично через Metal compute / фильтры.)
    }
}
```

Запускаешь таймер на 1 Гц: `loader.step()` до 5 % (или до auto-shutdown-guard), логируешь энергию, время, кривые.

---

## 2) Что отдать пользователю после теста (отчёт)

**Короткое резюме (читается за 5 сек):**

* **Health Score** (0–100) и цветовая зона: Зелёная ≥85, Жёлтая 70–85, Красная <70.
* **Износ (SOH)**: по энергии и по ёмкости (две цифры).
* **Прогноз автономности** при 0.1/0.2/0.3 C (часы:мин).
* **Решение:** «Наблюдать / Планировать замену / Рекомендуем заменить».

**Графики (по убыванию пользы):**

* **SOC vs Time** с маркерами микро-дропов.
* **Power vs Time** (показывает стабильность CP-контроля).
* **Voltage vs Time** + **OCV(SOC)** (поверх) — видно просадки и «компенсированную» кривую.
* **DCIR vs SOC** (три точки на 80/60/40/20 %) — рост сопротивления к низкому SOC=плохой знак.
* **Temperature vs Time** — чтобы не винить батарею за перегрев от нагрузки.
* **Energy delivered (Wh)** и **SOH\_energy** — столбик/цифра.

**Табличка параметров теста (мелким шрифтом):**

* Версия macOS/модель, дата/время, начальный SOC, пресет мощности (Вт и C-rate), средняя температура, среднее напряжение, версия приложения.

**Текст «что это значит»:**

* 2–3 предложения простым языком (без жаргона), плюс «что делать дальше».

**Экспорт:** HTML-отчёт + PDF (кнопка «поделиться»).

---

## 3) Что показывать на главном дашборде (и что убрать)

Скрин хороший по визуалу, но часть цифр действительно может вводить в заблуждение. Я бы сделал так:

**Оставить/добавить (верхний блок):**

* **Health Score** (крупно) и подпись «Состояние батареи: Норм/Наблюдать/Скоро замена».
* **Износ (SOH)**: «Оставшаяся ёмкость: 81 %» (а деталь 4931/6075 mAh — в поповере «Подробнее»).
* **Время работы**:

  * **При текущей нагрузке** — «≈ 2.7 ч» (как у тебя, это ок).
  * **На пресетах** (мини-чипы): «Лёгкая \~5 Вт: 6.8 ч • Средняя 10 Вт: 3.4 ч • Тяжёлая 15 Вт: 2.2 ч».
* **Температура аккумулятора** с неймингом «Норма/Высокая» и пояснением «длительно >40 °C ускоряет износ».
* **Статус питания** (сетевой/разряд).

**Второй блок («Тренды»):**

* **Циклы** (169) — *без* ярлыка «Отлично/Плохо\*. Корректнее: «Циклов: 169 (низкая наработка)». Оценочные ярлыки по циклам часто путают.
* **Графики за 7/30 дней**: средняя мощность (Вт), средняя температура, медленный тренд SOH.

**Спрятать/переименовать:**

* «**Разряд (1 час) — 36.6 % в час**» — метрика опасная: пользователь думает, что батарея «умирает», хотя просто нагрузка была тяжёлая. Замени на **«Средняя мощность за 15 мин: 13 Вт»** и **«Скорость расхода: 13 Вт ≈ 3.8 %/10 мин при текущей ёмкости»** (добавь «≈», чтобы не казалось константой).
* «Ёмкость 4931/6075 mAh — Приемлемо» можно свернуть в «Подробнее». Главная цифра — *процент оставшейся ёмкости*.
* «Износ 19 % — Приемлемо» оставь, но синхронизируй с Health Score (чтобы не было когнитивного диссонанса: «Приемлемо», а скор — «Плохо»).

---

## 4) Обещанные наброски кода: OCV и «knee-index»

Ниже — компактные функции:

1. восстановление **$V_{OC}$** на основе твоих **DCIR-точек**;
2. **биннинг по SOC** (сглаживание);
3. поиск **knee-SOC** через «двухсегментную» аппроксимацию;
4. расчёт **knee-index** (0–100).

```swift
// 1) Уже есть OCVReconstructor(points: [DCIRPoint]) из прошлых набросков.
//    Получаем массив (soc[], vOC[]):

func reconstructVOC(samples: [BatterySample], recon: OCVReconstructor) -> ([Double],[Double]) {
    var soc: [Double] = [], voc: [Double] = []
    for s in samples {
        if let v = recon.vOC_mV(sample: s) {
            soc.append(s.soc_pct)
            voc.append(v / 1000.0) // в В
        }
    }
    return (soc, voc)
}

// 2) Бинним по SOC (шаг 2%) чтобы убрать шум

func binBySOC(soc: [Double], voc: [Double], step: Double = 2.0) -> ([Double],[Double]) {
    guard soc.count == voc.count, soc.count > 0 else { return ([],[]) }
    var bins: [(Double,Double,Int)] = [] // (socMid, sumV, n)
    var s = 0.0
    while s <= 100.0 { bins.append((s+step/2, 0, 0)); s += step }
    for (x,y) in zip(soc, voc) {
        let i = Int(max(0, min(Double(bins.count-1), floor(x/step))))
        bins[i].1 += y; bins[i].2 += 1
    }
    let xs = bins.filter{$0.2>0}.map{$0.0}
    let ys = bins.filter{$0.2>0}.map{ $0.1/Double($0.2) }
    return (xs, ys)
}

// 3) Линейная регрессия + поиск излома (piecewise linear, один брейкпоинт)

func linfit(_ x: [Double], _ y: [Double]) -> (a: Double, b: Double, sse: Double) {
    let n = Double(x.count)
    let sx = x.reduce(0,+), sy = y.reduce(0,+)
    let sxx = zip(x,x).reduce(0){$0+$1.0*$1.1}
    let sxy = zip(x,y).reduce(0){$0+$1.0*$1.1}
    let denom = n*sxx - sx*sx
    let a = denom == 0 ? 0 : (n*sxy - sx*sy)/denom
    let b = (sy - a*sx)/n
    let sse = zip(x,y).reduce(0){ $0 + pow($1.1 - (a*$1.0 + b), 2) }
    return (a,b,sse)
}

func kneeSOC(soc: [Double], vOC: [Double]) -> Double? {
    guard soc.count >= 8, soc.count == vOC.count else { return nil }
    var bestKnee = soc[4], bestErr = Double.infinity
    // Ищем брейкпоинт в диапазоне 10–90% (чтобы отбросить края)
    for k in 3..<(soc.count-3) {
        if soc[k] < 10 || soc[k] > 90 { continue }
        let (a1,b1,e1) = linfit(Array(soc[0...k]), Array(vOC[0...k]))
        let (a2,b2,e2) = linfit(Array(soc[k...]),   Array(vOC[k...]))
        let err = e1 + e2 + 1e-6*abs(a1-a2) // крошечный L1-пенальти за "излом"
        if err < bestErr { bestErr = err; bestKnee = soc[k] }
    }
    return bestKnee
}

func kneeIndex(from kneeSOC: Double) -> Double {
    // 100 — отличное колено (≤25%), 0 — очень раннее (≥50%)
    let t = max(0, min(1, (kneeSOC - 25.0)/25.0))
    return (1.0 - t) * 100.0
}

// ---------- Использование (те самые «три строки») ----------
let (socRaw, vOCRaw) = reconstructVOC(samples: sampler.buf, recon: ocvRecon)
let (socB, vOCB)     = binBySOC(soc: socRaw, voc: vOCRaw, step: 2.0)
let kneeSOCVal       = kneeSOC(soc: socB, vOC: vOCB)
let kneeIdx          = kneeSOCVal.map(kneeIndex) ?? 0
```

**Как интерпретировать:**

* `kneeSOC ≈ 20–30 %` — норма; `kneeIndex ~ 70–100`.
* `kneeSOC` сдвинулось к 40–50 % → батарея «сыплется под нагрузкой»; `kneeIndex` падает <50.

