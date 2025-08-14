import Foundation
import AppKit

enum ReportGenerator {
    private static func loadResourceText(name: String, ext: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
    static func generateHTML(result: BatteryAnalysis,
                             snapshot: BatterySnapshot,
                             history: [BatteryReading],
                             calibration: CalibrationResult?) -> URL? {
        let df = ISO8601DateFormatter()
        let recent = history

        let rows = recent.map { r in
            "<tr><td>\(df.string(from: r.timestamp))</td><td>\(r.percentage)%</td><td>\(r.isCharging ? "Да" : "Нет")</td><td>\(String(format: "%.2f", r.voltage)) V</td><td>\(String(format: "%.1f", r.temperature)) °C</td></tr>"
        }.joined()

        // Prepare data for interactive charts (safe JSON, no manual escaping)
        let itemsForJson: [[String: Any]] = recent.map { r in
            return [
                "t": df.string(from: r.timestamp),
                "p": r.percentage,
                "c": r.isCharging,
                "v": Double(String(format: "%.3f", r.voltage)) ?? r.voltage,
                "temp": Double(String(format: "%.2f", r.temperature)) ?? r.temperature
            ]
        }
        let jsonData: Data = (try? JSONSerialization.data(withJSONObject: ["items": itemsForJson], options: [])) ?? Data("{\"items\":[]}".utf8)
        let jsonText: String = String(data: jsonData, encoding: String.Encoding.utf8) ?? "{\"items\":[]}"
        let eFullWh: String = {
            let cap = snapshot.maxCapacity
            let volt = snapshot.voltage
            if cap > 0 && volt > 0 {
                return String(format: "%.3f", (Double(cap) / 1000.0) * volt)
            } else {
                return "null"
            }
        }()
        let uplotCSS = loadResourceText(name: "uPlot.min", ext: "css") ?? ""
        let uplotJS = loadResourceText(name: "uPlot.iife.min", ext: "js") ?? ""

        var calibrationHTML = ""
        if let c = calibration {
            calibrationHTML = """
            <div class=\"card\" style=\"margin-bottom: 16px;\">
              <div class=\"muted\">Сеанс анализа</div>
              <div>Проведён: \(df.string(from: c.startedAt)) → \(df.string(from: c.finishedAt))</div>
              <div>Средний разряд: \(String(format: "%.1f", c.avgDischargePerHour)) %/ч • Прогноз автономности: \(String(format: "%.1f", c.estimatedRuntimeFrom100To0Hours)) ч</div>
            </div>
            """
        }

        // Precompute text to simplify interpolation inside HTML literal
        let wearText = String(format: "%.0f%%", snapshot.wearPercent)
        let avgDisText = String(format: "%.1f", result.avgDischargePerHour)
        let trendDisText = String(format: "%.1f", result.trendDischargePerHour)
        let runtimeText = String(format: "%.1f", result.estimatedRuntimeFrom100To0Hours)
        let anomaliesHTML: String = {
            if result.anomalies.isEmpty { return "" }
            let items = result.anomalies.map { "<li>\($0)</li>" }.joined()
            return "<ul style='margin-top: 8px;'>" + items + "</ul>"
        }()

        let html = """
        <!doctype html>
        <html lang=\"ru\">
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
          <title>BatMon • Отчёт</title>
          <style>
            :root { --bg:#0f172a; --card:#111827; --fg:#e2e8f0; --muted:#94a3b8; --accent:#93c5fd; --accent2:#34d399; }
            body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; background: var(--bg); color: var(--fg); padding: 24px; }
            .wrap { max-width: 1100px; margin: 0 auto; }
            h1 { font-size: 24px; margin: 0 0 8px; }
            .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
            .card { background: var(--card); border-radius: 12px; padding: 16px; }
            .muted { color: var(--muted); font-size: 12px; }
            .tabs { display: flex; gap: 8px; margin: 16px 0 8px; flex-wrap: wrap; }
            .tab { background: #0b1220; border: 1px solid #1f2937; color: var(--fg); border-radius: 8px; padding: 6px 10px; cursor: pointer; font-size: 12px; }
            .tab.active { border-color: var(--accent); color: var(--accent); }
            .tabc { display: none; }
            .tabc.active { display: block; }
            .chart { height: 320px; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; }
            th, td { border-bottom: 1px solid #1f2937; padding: 6px 8px; text-align: left; }
            th { color: var(--accent); }
            /* uPlot CSS */
            \(uplotCSS)
          </style>
        </head>
        <body>
         <div class=\"wrap\">
           <h1>Отчёт BatMon</h1>
           <div class=\"muted\">Сгенерировано: \(df.string(from: Date()))</div>

           <div class=\"grid\" style=\"margin:16px 0 20px;\">
             <div class=\"card\">
               <div class=\"muted\">Текущий заряд</div>
               <div style=\"font-size:20px;font-weight:600;\">\(snapshot.percentage)%</div>
             </div>
             <div class=\"card\">
              <div class=\"muted\">Износ</div>
                 <div style=\"font-size:20px;font-weight:600;\">\(wearText)</div>
             </div>
             <div class=\"card\">
               <div class=\"muted\">Циклы</div>
               <div style=\"font-size:20px;font-weight:600;\">\(snapshot.cycleCount)</div>
             </div>
             <div class=\"card\">
               <div class=\"muted\">Здоровье</div>
               <div style=\"font-size:20px;font-weight:600;\">\(result.healthScore)/100</div>
             </div>
           </div>

             <div class=\"card\" style=\"margin-bottom: 16px;\"> 
              <div class=\"muted\">Рекомендация</div>
              <div style=\"font-size:16px;font-weight:600;\">\(result.recommendation)</div>
              <div class=\"muted\" style=\"margin-top:8px;\"> 
                 Разряд: \(avgDisText) %/ч • Тренд: \(trendDisText) %/ч •
                 Прогноз автономности: \(runtimeText) ч •
                 Микро‑просадки: \(result.microDropEvents)
              </div>
              \(anomaliesHTML)
            </div>

           \(calibrationHTML)

           <div class=\"tabs\">
             <button class=\"tab active\" data-target=\"tab-pct\">Заряд</button>
             <button class=\"tab\" data-target=\"tab-rate\">Разряд %/ч</button>
             <button class=\"tab\" data-target=\"tab-vt\">V / °C</button>
              <button class=\"tab\" data-target=\"tab-w\">Вт</button>
           </div>

           <div class=\"card tabc active\" id=\"tab-pct\">
             <div class=\"muted\" style=\"margin-bottom:6px;\">Процент заряда</div>
             <div id=\"chart-pct\" class=\"chart\"></div>
           </div>

           <div class=\"card tabc\" id=\"tab-rate\">
             <div class=\"muted\" style=\"margin-bottom:6px;\">Скорость разряда (%/ч)</div>
             <div id=\"chart-rate\" class=\"chart\"></div>
           </div>

           <div class=\"card tabc\" id=\"tab-vt\">
             <div class=\"muted\" style=\"margin-bottom:6px;\">Напряжение и температура</div>
             <div id=\"chart-vt\" class=\"chart\"></div>
           </div>

           <div class=\"card tabc\" id=\"tab-w\">
             <div class=\"muted\" style=\"margin-bottom:6px;\">Потребление (Вт)</div>
             <div id=\"chart-w\" class=\"chart\"></div>
             <div class=\"muted\" id=\"w-note\"></div>
           </div>

            <script type="application/json" id="readings-json">\(jsonText)</script>
         </div>

         <script>\(uplotJS)</script>
         <script>
           const data = JSON.parse(document.getElementById('readings-json').textContent);
           const items = data.items || [];
           const x = items.map(r => new Date(r.t).getTime());
           const pct = items.map(r => r.p);
           const volt = items.map(r => r.v);
           const temp = items.map(r => r.temp);
           const charging = items.map(r => !!r.c);
           const eFullWh = \(eFullWh);

           function containerWidth(el) { return Math.min(1070, el.clientWidth); }
           function mkBandsCharging() {
             const bands = [];
             let start = null;
             for (let i=0;i<charging.length;i++) {
               const xi = x[i];
               if (charging[i] && start===null) start = xi;
               if (!charging[i] && start!==null) { bands.push([start, xi]); start = null; }
             }
             if (start!==null) bands.push([start, x[x.length-1]]);
             return bands;
           }
           function mkMicroDropMarkers() {
             const ev = new Array(pct.length).fill(null);
             for (let i=1;i<pct.length;i++) {
               const dt = (x[i]-x[i-1]) / 1000; // seconds
               const d = pct[i] - pct[i-1];
               if (!charging[i] && !charging[i-1] && dt <= 120 && d <= -2) { ev[i] = pct[i]; }
             }
             return ev;
           }
           function dischargeRatePctPerHour(windowSec = 1800) {
             const rate = new Array(pct.length).fill(null);
             let j = 0;
             for (let i=0;i<pct.length;i++) {
               const t = x[i];
               while (j < i && t - x[j] > windowSec*1000) j++;
               const dt = (t - x[j]) / 3600000; // hours
               if (dt > 0) {
                 const startPct = pct[j];
                 const endPct = pct[i];
                 const anyCh = charging.slice(j, i+1).some(Boolean);
                 if (!anyCh && startPct != null && endPct != null) {
                   const d = startPct - endPct;
                   rate[i] = Math.max(0, d / dt);
                 }
               }
             }
             return rate;
           }
           function powerWattsFromRate(rate) { if (eFullWh == null) return null; return rate.map(r => r==null?null:(r/100)*eFullWh); }
           const bands = mkBandsCharging();
           const drops = mkMicroDropMarkers();
           const rate = dischargeRatePctPerHour();
           const watts = powerWattsFromRate(rate);
           const shadeCharging = { hooks: { draw: (u) => { const ctx = u.ctx; ctx.save(); ctx.fillStyle = 'rgba(16,185,129,0.10)'; bands.forEach(([a,b])=>{ const x0 = u.valToPos(a, 'x', true); const x1 = u.valToPos(b, 'x', true); ctx.fillRect(x0, u.bbox.top, x1 - x0, u.bbox.height); }); ctx.restore(); } } };
           const charts = {};
           function mkPctChart() { const el = document.getElementById('chart-pct'); const u = new uPlot({ width: containerWidth(el), height: 320, scales: { x: { time: true }, y: { range: [0, 100] } }, axes: [ {}, { values: (u,vals)=>vals.map(v=>v+'%') } ], series: [ {}, { label: '%', stroke: '#93c5fd', width: 2, fill: 'rgba(147,197,253,0.12)' }, { label: 'drops', stroke: 'transparent', width: 0, points: { size: 6, width: 2, stroke: '#f59e0b', fill: 'rgba(245,158,11,0.5)' } } ], legend: { live: true }, cursor: { drag: { x: true, y: false, setScale: true } }, plugins: [shadeCharging] }, [x, pct, drops], el); charts.pct = u; }
           function mkRateChart() { const el = document.getElementById('chart-rate'); const u = new uPlot({ width: containerWidth(el), height: 320, scales: { x: { time: true }, y: { range: [0, (u)=>Math.max(5, (u.series[1].max||0)*1.1)] } }, axes: [ {}, { values: (u,vals)=>vals.map(v=>v+' %/ч') } ], series: [ {}, { label: '%/ч', stroke: '#60a5fa', width: 2, fill: 'rgba(96,165,250,0.12)' } ], legend: { live: true }, cursor: { drag: { x: true, y: false, setScale: true } } }, [x, rate], el); charts.rate = u; }
           function mkVTChart() { const el = document.getElementById('chart-vt'); const u = new uPlot({ width: containerWidth(el), height: 320, scales: { x: { time: true }, y: { }, temp: { } }, axes: [ {}, { label: 'V', side: 3 }, { label: '°C', scale: 'temp', side: 1 } ], series: [ {}, { label: 'V', stroke: '#34d399', width: 2 }, { label: '°C', stroke: '#fca5a5', width: 2, scale: 'temp' } ], legend: { live: true }, cursor: { drag: { x: true, y: false, setScale: true } } }, [x, volt, temp], el); charts.vt = u; }
           function mkWChart() { const el = document.getElementById('chart-w'); const note = document.getElementById('w-note'); if (eFullWh == null) { note.textContent = 'Недоступно: недостаточно данных о ёмкости/напряжении.'; return; } const u = new uPlot({ width: containerWidth(el), height: 320, scales: { x: { time: true } }, axes: [ {}, { label: 'Вт' } ], series: [ {}, { label: 'Вт', stroke: '#f472b6', width: 2, fill: 'rgba(244,114,182,0.12)' } ], legend: { live: true }, cursor: { drag: { x: true, y: false, setScale: true } } }, [x, watts], el); charts.w = u; }
           function onResize() { requestAnimationFrame(()=>{ for (const id in charts) { const chartEl = charts[id].root.parentElement; charts[id].setSize({ width: containerWidth(chartEl), height: 320 }); } }); }
           function mountTabs() { const tabs = Array.from(document.querySelectorAll('.tab')); tabs.forEach(btn => { btn.addEventListener('click', () => { tabs.forEach(b=>b.classList.remove('active')); document.querySelectorAll('.tabc').forEach(c=>c.classList.remove('active')); btn.classList.add('active'); const id = btn.getAttribute('data-target'); document.getElementById(id).classList.add('active'); onResize(); }); }) }
           // init
           mkPctChart(); mkRateChart(); mkVTChart(); mkWChart();
           mountTabs();
           window.addEventListener('resize', onResize);
         </script>
        </body>
        </html>
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BatMon_Report_\(Int(Date().timeIntervalSince1970)).html")
        do {
            try html.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            return url
        } catch {
            return nil
        }
    }

    // Legacy sparkline removed in favor of uPlot interactive charts
}
