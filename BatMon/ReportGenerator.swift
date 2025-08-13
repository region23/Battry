import Foundation
import AppKit

enum ReportGenerator {
    static func generateHTML(result: BatteryAnalysis,
                             snapshot: BatterySnapshot,
                             history: [BatteryReading],
                             calibration: CalibrationResult?) -> URL? {
        let df = ISO8601DateFormatter()
        let recent = history

        let rows = recent.map { r in
            "<tr><td>\(df.string(from: r.timestamp))</td><td>\(r.percentage)%</td><td>\(r.isCharging ? "Да" : "Нет")</td><td>\(String(format: "%.2f", r.voltage)) V</td><td>\(String(format: "%.1f", r.temperature)) °C</td></tr>"
        }.joined()

        let spark = svgSparkline(for: Array(recent.suffix(600)), height: 60, width: 800)

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

        let html = """
        <!doctype html>
        <html lang="ru">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>BatMon • Отчёт</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; }
            .wrap { max-width: 1100px; margin: 0 auto; }
            h1 { font-size: 24px; margin: 0 0 8px; }
            .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
            .card { background: #111827; border-radius: 12px; padding: 16px; }
            .muted { color: #94a3b8; font-size: 12px; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; }
            th, td { border-bottom: 1px solid #1f2937; padding: 6px 8px; text-align: left; }
            th { color: #93c5fd; }
          </style>
        </head>
        <body>
         <div class="wrap">
           <h1>Отчёт BatMon</h1>
           <div class="muted">Сгенерировано: \(df.string(from: Date()))</div>

           <div class="grid" style="margin:16px 0 20px;">
             <div class="card">
               <div class="muted">Текущий заряд</div>
               <div style="font-size: 20px; font-weight: 600;">\(snapshot.percentage)%</div>
             </div>
             <div class="card">
               <div class="muted">Износ</div>
               <div style="font-size: 20px; font-weight: 600;">\(String(format: "%.0f%%", snapshot.wearPercent))</div>
             </div>
             <div class="card">
               <div class="muted">Циклы</div>
               <div style="font-size: 20px; font-weight: 600;">\(snapshot.cycleCount)</div>
             </div>
             <div class="card">
               <div class="muted">Здоровье</div>
               <div style="font-size: 20px; font-weight: 600;">\(result.healthScore)/100</div>
             </div>
           </div>

           <div class="card" style="margin-bottom: 16px;">
             <div class="muted">Рекомендация</div>
             <div style="font-size: 16px; font-weight: 600;">\(result.recommendation)</div>
             <div class="muted" style="margin-top: 8px;">
                Разряд: \(String(format: "%.1f", result.avgDischargePerHour)) %/ч • Тренд: \(String(format: "%.1f", result.trendDischargePerHour)) %/ч •
                Прогноз автономности: \(String(format: "%.1f", result.estimatedRuntimeFrom100To0Hours)) ч •
                Микро‑просадки: \(result.microDropEvents)
             </div>
             \(result.anomalies.isEmpty ? "" : "<ul style='margin-top: 8px;'>\(result.anomalies.map { "<li>\($0)</li>" }.joined())</ul>")
           </div>

           \(calibrationHTML)

           <div class="card" style="margin-bottom: 16px;">
             <div class="muted" style="margin-bottom: 6px;">Спарклайн заряда</div>
             \(spark)
           </div>

           <div class="card">
             <div class="muted" style="margin-bottom: 6px;">Последние измерения</div>
             <table>
               <thead>
                  <tr><th>Время</th><th>%</th><th>Зарядка</th><th>V</th><th>°C</th></tr>
               </thead>
               <tbody>
                  \(rows)
               </tbody>
             </table>
           </div>
         </div>
        </body>
        </html>
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BatMon_Report_\(Int(Date().timeIntervalSince1970)).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func svgSparkline(for history: [BatteryReading], height: Int, width: Int) -> String {
        guard history.count >= 2 else { return "<svg width='\(width)' height='\(height)'></svg>" }
        let h = Double(height)
        let w = Double(width)
        let xs = (0..<history.count).map { Double($0) / Double(history.count - 1) * w }
        let ys = history.map { (1.0 - Double($0.percentage) / 100.0) * (h - 8) + 4 }
        var d = "M \(xs[0]),\(ys[0]) "
        for i in 1..<xs.count { d += "L \(xs[i]),\(ys[i]) " }
        return "<svg width='\(width)' height='\(height)'><path d='\(d)' fill='none' stroke='#93c5fd' stroke-width='2'/></svg>"
    }
}
