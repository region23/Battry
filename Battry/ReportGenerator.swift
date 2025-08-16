import Foundation
import AppKit


/// Генерация HTML‑отчёта с графиками на основе истории и снимка
enum ReportGenerator {
    /// Загружает текстовый ресурс из бандла
    private static func loadResourceText(name: String, ext: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
    
    /// Загружает изображение из бандла и конвертирует в base64 data URL
    private static func loadImageAsDataURL(named: String) -> String? {
        #if os(macOS)
        guard let image = NSImage(named: named),
              let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let base64String = pngData.base64EncodedString()
        return "data:image/png;base64,\(base64String)"
        #else
        return nil
        #endif
    }
    
    /// Определяет предпочитаемый язык для отчёта
    private static func getReportLanguage() -> String {
        return Localization.shared.language.rawValue
    }
    
    /// Возвращает локализованную строку для отчёта
    private static func localizedString(_ key: String) -> String {
        return Localization.shared.t(key)
    }
    /// Создаёт HTML‑отчёт и сохраняет в постоянную директорию
    static func generateHTML(result: BatteryAnalysis,
                             snapshot: BatterySnapshot,
                             history: [BatteryReading],
                             calibration: CalibrationResult?) -> URL? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let isoFormatter = ISO8601DateFormatter()
        let lang = getReportLanguage()
        let recent = history

        // Готовим данные для интерактивных графиков (безопасный JSON)
        let itemsForJson: [[String: Any]] = recent.map { r in
            return [
                "t": isoFormatter.string(from: r.timestamp),
                "p": r.percentage,
                "c": r.isCharging,
                "v": Double(String(format: "%.3f", r.voltage)) ?? r.voltage,
                "temp": Double(String(format: "%.2f", r.temperature)) ?? r.temperature
            ]
        }
        let jsonData: Data = (try? JSONSerialization.data(withJSONObject: ["items": itemsForJson], options: [])) ?? Data("{\"items\":[]}".utf8)
        let jsonText: String = String(data: jsonData, encoding: String.Encoding.utf8) ?? "{\"items\":[]}"
        
        // Полная энергия батареи (оценка) в Вт⋅ч: (mAh/1000)*V
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
        
        // Загружаем логотип Battry
        let logoDataURL = loadImageAsDataURL(named: "battry_logo_alpha_horizontal")

        // Device info
        let deviceModel = {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machine = withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(validatingUTF8: $0) ?? "Unknown Mac"
                }
            }
            return machine
        }()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        // Health status calculation
        let healthStatus: (color: String, label: String) = {
            let score = result.healthScore
            if score >= 85 { return ("success", lang == "ru" ? "Отлично" : "Excellent") }
            if score >= 70 { return ("warning", lang == "ru" ? "Хорошо" : "Good") }
            if score >= 50 { return ("orange", lang == "ru" ? "Удовлетворительно" : "Fair") }
            return ("danger", lang == "ru" ? "Требует внимания" : "Needs Attention")
        }()
        
        // Generate calibration section
        let calibrationHTML: String = {
            guard let c = calibration else { return "" }
            let startDateStr = df.string(from: c.startedAt)
            let endDateStr = df.string(from: c.finishedAt)
            let durationStr = String(format: "%.1f", c.durationHours)
            let avgDischargeStr = String(format: "%.1f", c.avgDischargePerHour)
            let runtimeStr = String(format: "%.1f", c.estimatedRuntimeFrom100To0Hours)
            
            return """
            <div class="card calibration-card">
              <div class="card-header">
                <div class="card-icon">🔋</div>
                <h3>\(lang == "ru" ? "Результаты тестирования" : "Calibration Test Results")</h3>
              </div>
              <div class="card-content">
                <div class="test-details">
                  <div class="detail-row">
                    <span class="label">\(lang == "ru" ? "Период тестирования:" : "Test Period:")</span>
                    <span class="value">\(startDateStr) → \(endDateStr)</span>
                  </div>
                  <div class="detail-row">
                    <span class="label">\(lang == "ru" ? "Длительность:" : "Duration:")</span>
                    <span class="value">\(durationStr) \(lang == "ru" ? "ч" : "h")</span>
                  </div>
                  <div class="metrics-grid">
                    <div class="metric-card">
                      <div class="metric-value">\(avgDischargeStr)</div>
                      <div class="metric-label">\(lang == "ru" ? "%/ч разряд" : "%/h discharge")</div>
                    </div>
                    <div class="metric-card">
                      <div class="metric-value">\(runtimeStr)</div>
                      <div class="metric-label">\(lang == "ru" ? "ч автономность" : "h runtime")</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            """
        }()

        // Prepare formatted values
        let wearText = String(format: "%.0f%%", snapshot.wearPercent)
        let avgDisText = String(format: "%.1f", result.avgDischargePerHour)
        let trendDisText = String(format: "%.1f", result.trendDischargePerHour)
        let runtimeText = String(format: "%.1f", result.estimatedRuntimeFrom100To0Hours)
        
        // Generate anomalies section
        let anomaliesHTML: String = {
            if result.anomalies.isEmpty { return "" }
            let anomaliesTitle = lang == "ru" ? "Обнаруженные аномалии:" : "Detected Anomalies:"
            let items = result.anomalies.map { "<li class=\"anomaly-item\">⚠️ \($0)</li>" }.joined()
            return """
            <div class="anomalies-section">
              <h4>\(anomaliesTitle)</h4>
              <ul class="anomalies-list">\(items)</ul>
            </div>
            """
        }()

        let html = """
        <!doctype html>
        <html lang=\"\(lang)\">
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, user-scalable=yes\">
          <title>Battry • \(lang == "ru" ? "Отчёт о состоянии батареи" : "Battery Health Report")</title>
          <meta name=\"description\" content=\"\(lang == "ru" ? "Подробный отчёт о состоянии батареи MacBook" : "Detailed MacBook battery health report")\">
          <style>
            /* CSS Custom Properties with Dark/Light Theme */
            :root {
              /* Light theme colors */
              --bg-primary: #ffffff;
              --bg-secondary: #f8fafc;
              --bg-card: #ffffff;
              --bg-card-elevated: #ffffff;
              --text-primary: #0f172a;
              --text-secondary: #475569;
              --text-muted: #94a3b8;
              --border-subtle: #e2e8f0;
              --border-default: #cbd5e1;
              --accent-primary: #3b82f6;
              --accent-secondary: #06b6d4;
              --success: #10b981;
              --warning: #f59e0b;
              --danger: #ef4444;
              --orange: #f97316;
              --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
              --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
              --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
              --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);
              --blur-backdrop: blur(16px);
              --gradient-primary: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              --gradient-success: linear-gradient(135deg, #84fab0 0%, #8fd3f4 100%);
              --gradient-warning: linear-gradient(135deg, #ffeaa7 0%, #fab1a0 100%);
              --gradient-danger: linear-gradient(135deg, #fd79a8 0%, #fdcb6e 100%);
            }

            /* Dark theme */
            @media (prefers-color-scheme: dark) {
              :root {
                --bg-primary: #0f172a;
                --bg-secondary: #1e293b;
                --bg-card: #1e293b;
                --bg-card-elevated: #334155;
                --text-primary: #f1f5f9;
                --text-secondary: #cbd5e1;
                --text-muted: #64748b;
                --border-subtle: #334155;
                --border-default: #475569;
                --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.3);
                --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.3), 0 2px 4px -2px rgb(0 0 0 / 0.3);
                --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.3), 0 4px 6px -4px rgb(0 0 0 / 0.3);
                --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.3), 0 8px 10px -6px rgb(0 0 0 / 0.3);
              }
            }

            /* Reset and base styles */
            * {
              box-sizing: border-box;
              margin: 0;
              padding: 0;
            }

            html {
              scroll-behavior: smooth;
              font-size: 16px;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              line-height: 1.6;
              color: var(--text-primary);
              background: var(--bg-primary);
              background-image: 
                radial-gradient(circle at 25% 25%, rgba(59, 130, 246, 0.05) 0%, transparent 25%),
                radial-gradient(circle at 75% 75%, rgba(16, 185, 129, 0.05) 0%, transparent 25%);
              min-height: 100vh;
              padding: clamp(1rem, 4vw, 2rem);
              overflow-x: auto;
            }

            /* Container and layout */
            .container {
              max-width: 1200px;
              margin: 0 auto;
              position: relative;
            }

            /* Header */
            .header {
              text-align: center;
              margin-bottom: 3rem;
              position: relative;
            }

            .header::after {
              content: '';
              position: absolute;
              bottom: -1rem;
              left: 50%;
              transform: translateX(-50%);
              width: 100px;
              height: 3px;
              background: var(--gradient-primary);
              border-radius: 2px;
            }

            .header-logo {
              max-width: 280px;
              max-height: 80px;
              width: auto;
              height: auto;
              margin: 0 auto 1rem;
              display: block;
              filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.1));
              transition: all 0.3s ease;
            }

            .header-logo:hover {
              transform: scale(1.02);
              filter: drop-shadow(0 6px 12px rgba(0, 0, 0, 0.15));
            }

            @media (prefers-color-scheme: dark) {
              .header-logo {
                filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.3)) brightness(1.1);
              }
              
              .header-logo:hover {
                filter: drop-shadow(0 6px 12px rgba(0, 0, 0, 0.4)) brightness(1.1);
              }
            }

            .header h1 {
              font-size: clamp(2rem, 5vw, 3rem);
              font-weight: 800;
              background: var(--gradient-primary);
              -webkit-background-clip: text;
              -webkit-text-fill-color: transparent;
              background-clip: text;
              margin-bottom: 0.5rem;
              letter-spacing: -0.02em;
            }

            /* Fallback text styling when logo is not available */
            .header-title-fallback {
              font-size: clamp(2rem, 5vw, 3rem);
              font-weight: 800;
              background: var(--gradient-primary);
              -webkit-background-clip: text;
              -webkit-text-fill-color: transparent;
              background-clip: text;
              margin-bottom: 0.5rem;
              letter-spacing: -0.02em;
            }

            .header .subtitle {
              color: var(--text-secondary);
              font-size: 1.1rem;
              margin-bottom: 0.25rem;
            }

            .header .timestamp {
              color: var(--text-muted);
              font-size: 0.9rem;
            }

            /* Device info bar */
            .device-info {
              background: var(--bg-card);
              border: 1px solid var(--border-subtle);
              border-radius: 1rem;
              padding: 1rem 1.5rem;
              margin-bottom: 2rem;
              display: flex;
              justify-content: space-between;
              align-items: center;
              flex-wrap: wrap;
              gap: 1rem;
              box-shadow: var(--shadow-sm);
            }

            .device-info .device-model {
              font-weight: 600;
              color: var(--text-primary);
            }

            .device-info .device-os {
              color: var(--text-secondary);
              font-size: 0.9rem;
            }

            /* Executive Summary */
            .executive-summary {
              background: var(--bg-card);
              border: 1px solid var(--border-subtle);
              border-radius: 1.5rem;
              padding: 2rem;
              margin-bottom: 2rem;
              box-shadow: var(--shadow-lg);
              position: relative;
              overflow: hidden;
            }

            .executive-summary::before {
              content: '';
              position: absolute;
              top: 0;
              left: 0;
              right: 0;
              height: 4px;
              background: var(--gradient-primary);
            }

            .summary-header {
              text-align: center;
              margin-bottom: 2rem;
            }

            .summary-header h2 {
              font-size: 1.8rem;
              font-weight: 700;
              color: var(--text-primary);
              margin-bottom: 0.5rem;
            }

            .health-score-container {
              display: flex;
              justify-content: center;
              align-items: center;
              margin: 2rem 0;
            }

            .health-score-ring {
              position: relative;
              width: 150px;
              height: 150px;
            }

            .health-score-ring svg {
              width: 100%;
              height: 100%;
              transform: rotate(-90deg);
            }

            .health-score-ring .bg-ring {
              fill: none;
              stroke: var(--border-subtle);
              stroke-width: 8;
            }

            .health-score-ring .progress-ring {
              fill: none;
              stroke-width: 8;
              stroke-linecap: round;
              transition: stroke-dashoffset 1s ease-in-out;
            }

            .health-score-ring .score-text {
              position: absolute;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%);
              text-align: center;
            }

            .health-score-ring .score-value {
              font-size: 2rem;
              font-weight: 800;
              color: var(--text-primary);
              line-height: 1;
            }

            .health-score-ring .score-label {
              font-size: 0.8rem;
              color: var(--text-secondary);
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }

            .health-status {
              text-align: center;
              margin-top: 1rem;
            }

            .health-badge {
              display: inline-flex;
              align-items: center;
              gap: 0.5rem;
              padding: 0.5rem 1rem;
              border-radius: 50px;
              font-weight: 600;
              font-size: 0.9rem;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }

            .health-badge.success {
              background: rgba(16, 185, 129, 0.1);
              color: var(--success);
              border: 1px solid rgba(16, 185, 129, 0.2);
            }

            .health-badge.warning {
              background: rgba(245, 158, 11, 0.1);
              color: var(--warning);
              border: 1px solid rgba(245, 158, 11, 0.2);
            }

            .health-badge.orange {
              background: rgba(249, 115, 22, 0.1);
              color: var(--orange);
              border: 1px solid rgba(249, 115, 22, 0.2);
            }

            .health-badge.danger {
              background: rgba(239, 68, 68, 0.1);
              color: var(--danger);
              border: 1px solid rgba(239, 68, 68, 0.2);
            }

            /* Main metrics grid */
            .metrics-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
              gap: 1.5rem;
              margin: 2rem 0;
            }

            /* Card component */
            .card {
              background: var(--bg-card);
              border: 1px solid var(--border-subtle);
              border-radius: 1rem;
              padding: 1.5rem;
              box-shadow: var(--shadow-md);
              transition: all 0.3s ease;
              position: relative;
              overflow: hidden;
            }

            .card:hover {
              transform: translateY(-2px);
              box-shadow: var(--shadow-xl);
            }

            .card-header {
              display: flex;
              align-items: center;
              gap: 0.75rem;
              margin-bottom: 1rem;
            }

            .card-icon {
              font-size: 1.5rem;
              display: flex;
              align-items: center;
              justify-content: center;
              width: 2.5rem;
              height: 2.5rem;
              border-radius: 0.75rem;
              background: rgba(59, 130, 246, 0.1);
            }

            .card-header h3 {
              font-size: 1.1rem;
              font-weight: 600;
              color: var(--text-primary);
            }

            .card-content {
              color: var(--text-secondary);
            }

            /* Metric cards */
            .metric-card {
              text-align: center;
              padding: 1.5rem;
              background: var(--bg-secondary);
              border-radius: 1rem;
              border: 1px solid var(--border-subtle);
              transition: all 0.2s ease;
            }

            .metric-card:hover {
              background: var(--bg-card-elevated);
              transform: translateY(-1px);
            }

            .metric-value {
              font-size: 2rem;
              font-weight: 800;
              color: var(--text-primary);
              margin-bottom: 0.25rem;
              line-height: 1;
            }

            .metric-label {
              font-size: 0.8rem;
              color: var(--text-muted);
              text-transform: uppercase;
              letter-spacing: 0.5px;
              font-weight: 500;
            }

            .metric-sublabel {
              font-size: 0.75rem;
              color: var(--text-muted);
              margin-top: 0.25rem;
            }

            /* Performance summary */
            .performance-summary {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 1rem;
              margin: 1.5rem 0;
            }

            .performance-item {
              display: flex;
              justify-content: space-between;
              align-items: center;
              padding: 1rem;
              background: var(--bg-secondary);
              border-radius: 0.75rem;
              border: 1px solid var(--border-subtle);
            }

            .performance-label {
              color: var(--text-secondary);
              font-size: 0.9rem;
            }

            .performance-value {
              font-weight: 600;
              color: var(--text-primary);
            }

            /* Anomalies section */
            .anomalies-section {
              margin-top: 1.5rem;
            }

            .anomalies-section h4 {
              color: var(--danger);
              font-size: 1rem;
              font-weight: 600;
              margin-bottom: 0.75rem;
              display: flex;
              align-items: center;
              gap: 0.5rem;
            }

            .anomalies-list {
              list-style: none;
              space-y: 0.5rem;
            }

            .anomaly-item {
              display: flex;
              align-items: center;
              gap: 0.5rem;
              padding: 0.75rem;
              background: rgba(239, 68, 68, 0.05);
              border: 1px solid rgba(239, 68, 68, 0.1);
              border-radius: 0.5rem;
              color: var(--danger);
              font-size: 0.9rem;
              margin-bottom: 0.5rem;
            }

            /* Charts section */
            .charts-section {
              margin: 3rem 0;
            }

            .section-header {
              text-align: center;
              margin-bottom: 2rem;
            }

            .section-header h2 {
              font-size: 1.8rem;
              font-weight: 700;
              color: var(--text-primary);
              margin-bottom: 0.5rem;
            }

            .section-subtitle {
              color: var(--text-secondary);
              font-size: 1rem;
            }

            /* Tabs */
            .tabs {
              display: flex;
              gap: 0.5rem;
              margin-bottom: 1.5rem;
              padding: 0.25rem;
              background: var(--bg-secondary);
              border-radius: 0.75rem;
              border: 1px solid var(--border-subtle);
              overflow-x: auto;
            }

            .tab {
              flex: 1;
              min-width: max-content;
              background: transparent;
              border: none;
              color: var(--text-secondary);
              border-radius: 0.5rem;
              padding: 0.75rem 1rem;
              cursor: pointer;
              font-size: 0.9rem;
              font-weight: 500;
              transition: all 0.2s ease;
              white-space: nowrap;
            }

            .tab:hover {
              background: var(--bg-card);
              color: var(--text-primary);
            }

            .tab.active {
              background: var(--bg-card);
              color: var(--accent-primary);
              box-shadow: var(--shadow-sm);
              font-weight: 600;
            }

            .tab-content {
              display: none;
            }

            .tab-content.active {
              display: block;
            }

            .chart-container {
              background: var(--bg-card);
              border: 1px solid var(--border-subtle);
              border-radius: 1rem;
              padding: 1.5rem;
              box-shadow: var(--shadow-md);
            }

            .chart-header {
              margin-bottom: 1rem;
            }

            .chart-title {
              font-size: 1.1rem;
              font-weight: 600;
              color: var(--text-primary);
              margin-bottom: 0.25rem;
            }

            .chart-subtitle {
              color: var(--text-muted);
              font-size: 0.9rem;
            }

            .chart {
              height: 400px;
              margin-top: 1rem;
            }

            /* Calibration specific styles */
            .calibration-card {
              border-left: 4px solid var(--accent-primary);
            }

            .test-details {
              space-y: 1rem;
            }

            .detail-row {
              display: flex;
              justify-content: space-between;
              align-items: center;
              padding: 0.75rem 0;
              border-bottom: 1px solid var(--border-subtle);
            }

            .detail-row:last-child {
              border-bottom: none;
            }

            .detail-row .label {
              color: var(--text-secondary);
              font-weight: 500;
            }

            .detail-row .value {
              color: var(--text-primary);
              font-weight: 600;
            }

            /* Footer */
            .footer {
              text-align: center;
              margin-top: 3rem;
              padding: 2rem;
              color: var(--text-muted);
              font-size: 0.9rem;
              border-top: 1px solid var(--border-subtle);
            }

            .footer a {
              color: var(--accent-primary);
              text-decoration: none;
              font-weight: 600;
            }

            .footer a:hover {
              text-decoration: underline;
            }

            /* Responsive design */
            @media (max-width: 768px) {
              .header-logo {
                max-width: 220px;
                max-height: 60px;
              }

              .metrics-grid {
                grid-template-columns: 1fr;
                gap: 1rem;
              }

              .performance-summary {
                grid-template-columns: 1fr;
              }

              .device-info {
                flex-direction: column;
                text-align: center;
              }

              .tabs {
                flex-direction: column;
              }

              .tab {
                text-align: center;
              }

              .chart {
                height: 300px;
              }
            }

            @media (max-width: 480px) {
              .header-logo {
                max-width: 180px;
                max-height: 50px;
              }
            }

            /* Print styles */
            @media print {
              body {
                background: white;
                color: black;
                padding: 0;
              }

              .container {
                max-width: none;
              }

              .header-logo {
                filter: none;
                max-width: 240px;
                max-height: 70px;
              }

              .card {
                break-inside: avoid;
                box-shadow: none;
                border: 1px solid #ccc;
              }

              .tabs,
              .tab {
                display: none;
              }

              .tab-content {
                display: block !important;
              }

              .chart {
                height: 300px;
              }
            }

            /* Custom uPlot overrides */
            \(uplotCSS)
            
            .u-legend {
              background: var(--bg-card) !important;
              border: 1px solid var(--border-subtle) !important;
              border-radius: 0.5rem !important;
              color: var(--text-primary) !important;
            }

            .u-tooltip {
              background: var(--bg-card) !important;
              border: 1px solid var(--border-subtle) !important;
              border-radius: 0.5rem !important;
              color: var(--text-primary) !important;
              box-shadow: var(--shadow-lg) !important;
            }
          </style>
        </head>
        <body>
          <div class=\"container\">
            <!-- Header -->
            <header class=\"header\">
              \(logoDataURL != nil ? 
                "<img src=\"\(logoDataURL!)\" alt=\"Battry\" class=\"header-logo\">" : 
                "<h1 class=\"header-title-fallback\">Battry</h1>"
              )
              <div class=\"subtitle\">\(lang == "ru" ? "Отчёт о состоянии батареи" : "Battery Health Report")</div>
              <div class=\"timestamp\">\(lang == "ru" ? "Сгенерировано" : "Generated"): \(df.string(from: Date()))</div>
            </header>

            <!-- Device Info -->
            <div class=\"device-info\">
              <div>
                <div class=\"device-model\">\(deviceModel)</div>
                <div class=\"device-os\">\(macOSVersion)</div>
              </div>
              <div>
                <div class=\"device-model\">\(lang == "ru" ? "Период данных" : "Data Period")</div>
                <div class=\"device-os\">\(recent.count) \(lang == "ru" ? "записей" : "records")</div>
              </div>
            </div>

            <!-- Executive Summary -->
            <section class=\"executive-summary\">
              <div class=\"summary-header\">
                <h2>\(lang == "ru" ? "Общая оценка" : "Executive Summary")</h2>
              </div>

              <div class=\"health-score-container\">
                <div class=\"health-score-ring\">
                  <svg viewBox=\"0 0 120 120\">
                    <circle class=\"bg-ring\" cx=\"60\" cy=\"60\" r=\"54\"></circle>
                    <circle class=\"progress-ring progress-ring-\(healthStatus.color)\" 
                            cx=\"60\" cy=\"60\" r=\"54\" 
                            stroke-dasharray=\"339.29\" 
                            stroke-dashoffset=\"\(339.29 * (1.0 - Double(result.healthScore) / 100.0))\"></circle>
                  </svg>
                  <div class=\"score-text\">
                    <div class=\"score-value\">\(result.healthScore)</div>
                    <div class=\"score-label\">\(lang == "ru" ? "из 100" : "/ 100")</div>
                  </div>
                </div>
              </div>

              <div class=\"health-status\">
                <div class=\"health-badge \(healthStatus.color)\">\(healthStatus.label)</div>
              </div>

              <div class=\"performance-summary\">
                <div class=\"performance-item\">
                  <span class=\"performance-label\">\(lang == "ru" ? "Средний разряд" : "Average Discharge")</span>
                  <span class=\"performance-value\">\(avgDisText) %/\(lang == "ru" ? "ч" : "h")</span>
                </div>
                <div class=\"performance-item\">
                  <span class=\"performance-label\">\(lang == "ru" ? "Тренд разряда" : "Discharge Trend")</span>
                  <span class=\"performance-value\">\(trendDisText) %/\(lang == "ru" ? "ч" : "h")</span>
                </div>
                <div class=\"performance-item\">
                  <span class=\"performance-label\">\(lang == "ru" ? "Прогноз автономности" : "Estimated Runtime")</span>
                  <span class=\"performance-value\">\(runtimeText) \(lang == "ru" ? "ч" : "h")</span>
                </div>
                <div class=\"performance-item\">
                  <span class=\"performance-label\">\(lang == "ru" ? "Микро-просадки" : "Micro-drops")</span>
                  <span class=\"performance-value\">\(result.microDropEvents)</span>
                </div>
              </div>

              <div class=\"card-content\">
                <h4 style=\"color: var(--text-primary); margin-bottom: 0.5rem;\">\(lang == "ru" ? "Рекомендация" : "Recommendation"):</h4>
                <p style=\"font-size: 1rem; line-height: 1.6;\">\(result.recommendation)</p>
                \(anomaliesHTML)
              </div>
            </section>

            <!-- Main Metrics -->
            <div class=\"metrics-grid\">
              <div class=\"card\">
                <div class=\"card-header\">
                  <div class=\"card-icon\">🔋</div>
                  <h3>\(lang == "ru" ? "Текущий заряд" : "Current Charge")</h3>
                </div>
                <div class=\"card-content\">
                  <div class=\"metric-value\">\(snapshot.percentage)%</div>
                  <div class=\"metric-sublabel\">
                    \(snapshot.isCharging ? (lang == "ru" ? "Заряжается" : "Charging") : (lang == "ru" ? "От батареи" : "On Battery"))
                  </div>
                </div>
              </div>

              <div class=\"card\">
                <div class=\"card-header\">
                  <div class=\"card-icon\">⚙️</div>
                  <h3>\(lang == "ru" ? "Износ батареи" : "Battery Wear")</h3>
                </div>
                <div class=\"card-content\">
                  <div class=\"metric-value\">\(wearText)</div>
                  <div class=\"metric-sublabel\">
                    \(snapshot.maxCapacity) / \(snapshot.designCapacity) mAh
                  </div>
                </div>
              </div>

              <div class=\"card\">
                <div class=\"card-header\">
                  <div class=\"card-icon\">🔄</div>
                  <h3>\(lang == "ru" ? "Циклы заряда" : "Charge Cycles")</h3>
                </div>
                <div class=\"card-content\">
                  <div class=\"metric-value\">\(snapshot.cycleCount)</div>
                  <div class=\"metric-sublabel\">
                    \(lang == "ru" ? "циклов" : "cycles")
                  </div>
                </div>
              </div>

              <div class=\"card\">
                <div class=\"card-header\">
                  <div class=\"card-icon\">🌡️</div>
                  <h3>\(lang == "ru" ? "Температура" : "Temperature")</h3>
                </div>
                <div class=\"card-content\">
                  <div class=\"metric-value\">\(String(format: "%.1f°C", snapshot.temperature))</div>
                  <div class=\"metric-sublabel\">
                    \(String(format: "%.2fV", snapshot.voltage))
                  </div>
                </div>
              </div>
            </div>

            \(calibrationHTML)

            <!-- Charts Section -->
            <section class=\"charts-section\">
              <div class=\"section-header\">
                <h2>\(lang == "ru" ? "Детальная аналитика" : "Detailed Analytics")</h2>
                <div class=\"section-subtitle\">\(lang == "ru" ? "Интерактивные графики данных батареи" : "Interactive battery data visualizations")</div>
              </div>

              <div class=\"tabs\">
                <button class=\"tab active\" data-target=\"tab-pct\">\(lang == "ru" ? "📊 Заряд" : "📊 Charge")</button>
                <button class=\"tab\" data-target=\"tab-rate\">\(lang == "ru" ? "📉 Разряд" : "📉 Discharge")</button>
                <button class=\"tab\" data-target=\"tab-vt\">\(lang == "ru" ? "⚡ Напряжение/Температура" : "⚡ Voltage/Temperature")</button>
                <button class=\"tab\" data-target=\"tab-w\">\(lang == "ru" ? "💡 Потребление" : "💡 Power")</button>
              </div>

              <div class=\"tab-content active\" id=\"tab-pct\">
                <div class=\"chart-container\">
                  <div class=\"chart-header\">
                    <div class=\"chart-title\">\(lang == "ru" ? "Уровень заряда батареи" : "Battery Charge Level")</div>
                    <div class=\"chart-subtitle\">\(lang == "ru" ? "Процент заряда во времени с отметками зарядки" : "Charge percentage over time with charging periods")</div>
                  </div>
                  <div id=\"chart-pct\" class=\"chart\"></div>
                </div>
              </div>

              <div class=\"tab-content\" id=\"tab-rate\">
                <div class=\"chart-container\">
                  <div class=\"chart-header\">
                    <div class=\"chart-title\">\(lang == "ru" ? "Скорость разряда" : "Discharge Rate")</div>
                    <div class=\"chart-subtitle\">\(lang == "ru" ? "Скорость разряда в процентах за час" : "Discharge rate in percent per hour")</div>
                  </div>
                  <div id=\"chart-rate\" class=\"chart\"></div>
                </div>
              </div>

              <div class=\"tab-content\" id=\"tab-vt\">
                <div class=\"chart-container\">
                  <div class=\"chart-header\">
                    <div class=\"chart-title\">\(lang == "ru" ? "Напряжение и температура" : "Voltage and Temperature")</div>
                    <div class=\"chart-subtitle\">\(lang == "ru" ? "Технические параметры батареи" : "Technical battery parameters")</div>
                  </div>
                  <div id=\"chart-vt\" class=\"chart\"></div>
                </div>
              </div>

              <div class=\"tab-content\" id=\"tab-w\">
                <div class=\"chart-container\">
                  <div class=\"chart-header\">
                    <div class=\"chart-title\">\(lang == "ru" ? "Потребление энергии" : "Power Consumption")</div>
                    <div class=\"chart-subtitle\">\(lang == "ru" ? "Потребление в ваттах" : "Power consumption in watts")</div>
                  </div>
                  <div id=\"chart-w\" class=\"chart\"></div>
                  <div id=\"w-note\" style=\"margin-top: 1rem; color: var(--text-muted); font-size: 0.9rem;\"></div>
                </div>
              </div>
            </section>

            <!-- Footer -->
            <footer class=\"footer\">
              <p>\(lang == "ru" ? "Сгенерировано приложением" : "Generated by") <a href=\"https://github.com/region23/Battry\" target=\"_blank\">Battry</a> • \(lang == "ru" ? "Мониторинг состояния батареи macOS" : "macOS Battery Health Monitoring")</p>
            </footer>

            <script type=\"application/json\" id=\"readings-json\">\(jsonText)</script>
          </div>
        
         <script>\(uplotJS)</script>
         <script>
           // Language settings
           const isRussian = '\(lang)' === 'ru';
           
           // Data preparation
           const data = JSON.parse(document.getElementById('readings-json').textContent);
           const items = data.items || [];
           const x = items.map(r => new Date(r.t).getTime() / 1000);
           const pct = items.map(r => r.p);
           const volt = items.map(r => r.v);
           const temp = items.map(r => r.temp);
           const charging = items.map(r => !!r.c);
           const eFullWh = \(eFullWh);
           
           // Chart themes
           const chartColors = {
             primary: getComputedStyle(document.documentElement).getPropertyValue('--accent-primary').trim() || '#3b82f6',
             secondary: getComputedStyle(document.documentElement).getPropertyValue('--accent-secondary').trim() || '#06b6d4',
             success: getComputedStyle(document.documentElement).getPropertyValue('--success').trim() || '#10b981',
             warning: getComputedStyle(document.documentElement).getPropertyValue('--warning').trim() || '#f59e0b',
             danger: getComputedStyle(document.documentElement).getPropertyValue('--danger').trim() || '#ef4444',
             textPrimary: getComputedStyle(document.documentElement).getPropertyValue('--text-primary').trim() || '#0f172a',
             textSecondary: getComputedStyle(document.documentElement).getPropertyValue('--text-secondary').trim() || '#475569',
             borderSubtle: getComputedStyle(document.documentElement).getPropertyValue('--border-subtle').trim() || '#e2e8f0'
           };

           // Enhanced utility functions
           function containerWidth(el) { 
             return Math.min(1100, Math.max(300, el.clientWidth - 32)); 
           }
           
           function formatTime(ts) {
             return new Date(ts * 1000).toLocaleString(isRussian ? 'ru-RU' : 'en-US', {
               hour: '2-digit',
               minute: '2-digit',
               month: 'short',
               day: 'numeric'
             });
           }
           
           // Charging bands for visualization
           function mkBandsCharging() {
             const bands = [];
             let start = null;
             for (let i = 0; i < charging.length; i++) {
               const xi = x[i];
               if (charging[i] && start === null) start = xi;
               if (!charging[i] && start !== null) { 
                 bands.push([start, xi]); 
                 start = null; 
               }
             }
             if (start !== null) bands.push([start, x[x.length - 1]]);
             return bands;
           }
           
           // Micro-drop detection for anomaly visualization
           function mkMicroDropMarkers() {
             const ev = new Array(pct.length).fill(null);
             for (let i = 1; i < pct.length; i++) {
               const dt = (x[i] - x[i - 1]);
               const d = pct[i] - pct[i - 1];
               if (!charging[i] && !charging[i - 1] && dt <= 120 && d <= -2) { 
                 ev[i] = pct[i]; 
               }
             }
             return ev;
           }
           
           // Enhanced discharge rate calculation
           function dischargeRatePctPerHour(windowSec = 1800) {
             const rate = new Array(pct.length).fill(null);
             let j = 0;
             for (let i = 0; i < pct.length; i++) {
               const t = x[i];
               while (j < i && t - x[j] > windowSec) j++;
               const dt = (t - x[j]) / 3600;
               if (dt > 0) {
                 const startPct = pct[j];
                 const endPct = pct[i];
                 const anyCh = charging.slice(j, i + 1).some(Boolean);
                 if (!anyCh && startPct != null && endPct != null) {
                   const d = startPct - endPct;
                   rate[i] = Math.max(0, d / dt);
                 }
               }
             }
             return rate;
           }
           
           function powerWattsFromRate(rate) { 
             if (eFullWh == null) return null; 
             return rate.map(r => r == null ? null : (r / 100) * eFullWh); 
           }
           
           // Prepare chart data
           const bands = mkBandsCharging();
           const drops = mkMicroDropMarkers();
           const rate = dischargeRatePctPerHour();
           const watts = powerWattsFromRate(rate);
           
           // Charging background plugin
           const shadeCharging = {
             hooks: {
               draw: (u) => {
                 const ctx = u.ctx;
                 ctx.save();
                 ctx.fillStyle = 'rgba(16, 185, 129, 0.08)';
                 bands.forEach(([a, b]) => {
                   const x0 = u.valToPos(a, 'x', true);
                   const x1 = u.valToPos(b, 'x', true);
                   ctx.fillRect(x0, u.bbox.top, x1 - x0, u.bbox.height);
                 });
                 ctx.restore();
               }
             }
           };
           
           // Progress ring animation
           function animateProgressRing() {
             const progressRings = document.querySelectorAll('.progress-ring');
             progressRings.forEach((ring, index) => {
               setTimeout(() => {
                 const healthScore = \(result.healthScore);
                 const circumference = 339.29;
                 const offset = circumference * (1 - healthScore / 100);
                 ring.style.strokeDashoffset = offset;
                 
                 // Set color based on health score
                 if (healthScore >= 85) ring.setAttribute('stroke', chartColors.success);
                 else if (healthScore >= 70) ring.setAttribute('stroke', chartColors.warning);
                 else if (healthScore >= 50) ring.setAttribute('stroke', '#f97316');
                 else ring.setAttribute('stroke', chartColors.danger);
               }, index * 200);
             });
           }
           
           // Chart storage
           const charts = {};
           
           // Common chart options
           const commonOpts = {
             cursor: {
               drag: { x: true, y: false, setScale: true },
               sync: { key: 'battry-charts' }
             },
             legend: { 
               live: true,
               mount: (self, legend) => {
                 legend.style.background = 'var(--bg-card)';
                 legend.style.border = '1px solid var(--border-subtle)';
                 legend.style.borderRadius = '0.5rem';
                 legend.style.color = 'var(--text-primary)';
               }
             },
             scales: {
               x: { 
                 time: true,
                 distr: 1
               }
             },
             axes: [
               {
                 stroke: chartColors.borderSubtle,
                 ticks: { stroke: chartColors.borderSubtle },
                 font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                 size: 12,
                 values: (self, vals) => vals.map(v => formatTime(v))
               }
             ]
           };
           
           // Battery percentage chart
           function mkPctChart() {
             const el = document.getElementById('chart-pct');
             const opts = {
               ...commonOpts,
               width: containerWidth(el),
               height: 400,
               scales: {
                 ...commonOpts.scales,
                 y: { range: [0, 100] }
               },
               axes: [
                 ...commonOpts.axes,
                 {
                   stroke: chartColors.borderSubtle,
                   ticks: { stroke: chartColors.borderSubtle },
                   font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                   size: 12,
                   values: (u, vals) => vals.map(v => v + '%')
                 }
               ],
               series: [
                 {},
                 {
                   label: isRussian ? 'Заряд %' : 'Charge %',
                   stroke: chartColors.primary,
                   width: 3,
                   fill: chartColors.primary + '20',
                   paths: u => uPlot.paths.spline()([u.data[0], u.data[1]], 0.5)
                 },
                 {
                   label: isRussian ? 'Микро-просадки' : 'Micro-drops',
                   stroke: 'transparent',
                   width: 0,
                   points: {
                     size: 8,
                     width: 3,
                     stroke: chartColors.warning,
                     fill: chartColors.warning + '80'
                   }
                 }
               ],
               plugins: [shadeCharging]
             };
             
             const u = new uPlot(opts, [x, pct, drops], el);
             charts.pct = u;
           }
           
           // Discharge rate chart
           function mkRateChart() {
             const el = document.getElementById('chart-rate');
             const opts = {
               ...commonOpts,
               width: containerWidth(el),
               height: 400,
               scales: {
                 ...commonOpts.scales,
                 y: { range: [0, (u) => Math.max(5, (u.series[1].max || 0) * 1.1)] }
               },
               axes: [
                 ...commonOpts.axes,
                 {
                   stroke: chartColors.borderSubtle,
                   ticks: { stroke: chartColors.borderSubtle },
                   font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                   size: 12,
                   values: (u, vals) => vals.map(v => v.toFixed(1) + (isRussian ? ' %/ч' : ' %/h'))
                 }
               ],
               series: [
                 {},
                 {
                   label: isRussian ? 'Разряд %/ч' : 'Discharge %/h',
                   stroke: chartColors.secondary,
                   width: 3,
                   fill: chartColors.secondary + '20'
                 }
               ]
             };
             
             const u = new uPlot(opts, [x, rate], el);
             charts.rate = u;
           }
           
           // Voltage and temperature chart
           function mkVTChart() {
             const el = document.getElementById('chart-vt');
             const opts = {
               ...commonOpts,
               width: containerWidth(el),
               height: 400,
               scales: {
                 ...commonOpts.scales,
                 y: {},
                 temp: {}
               },
               axes: [
                 ...commonOpts.axes,
                 {
                   label: 'V',
                   side: 3,
                   stroke: chartColors.borderSubtle,
                   ticks: { stroke: chartColors.borderSubtle },
                   font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                   size: 12,
                   values: (u, vals) => vals.map(v => v.toFixed(2) + 'V')
                 },
                 {
                   label: '°C',
                   scale: 'temp',
                   side: 1,
                   stroke: chartColors.borderSubtle,
                   ticks: { stroke: chartColors.borderSubtle },
                   font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                   size: 12,
                   values: (u, vals) => vals.map(v => v.toFixed(1) + '°C')
                 }
               ],
               series: [
                 {},
                 {
                   label: isRussian ? 'Напряжение (V)' : 'Voltage (V)',
                   stroke: chartColors.success,
                   width: 3
                 },
                 {
                   label: isRussian ? 'Температура (°C)' : 'Temperature (°C)',
                   stroke: chartColors.warning,
                   width: 3,
                   scale: 'temp'
                 }
               ]
             };
             
             const u = new uPlot(opts, [x, volt, temp], el);
             charts.vt = u;
           }
           
           // Power consumption chart
           function mkWChart() {
             const el = document.getElementById('chart-w');
             const note = document.getElementById('w-note');
             
             if (eFullWh == null) {
               note.textContent = isRussian ? 
                 'Недоступно: недостаточно данных о ёмкости/напряжении.' :
                 'Unavailable: insufficient capacity/voltage data.';
               return;
             }
             
             const opts = {
               ...commonOpts,
               width: containerWidth(el),
               height: 400,
               axes: [
                 ...commonOpts.axes,
                 {
                   label: isRussian ? 'Ватт' : 'Watts',
                   stroke: chartColors.borderSubtle,
                   ticks: { stroke: chartColors.borderSubtle },
                   font: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                   size: 12,
                   values: (u, vals) => vals.map(v => v.toFixed(1) + 'W')
                 }
               ],
               series: [
                 {},
                 {
                   label: isRussian ? 'Потребление (Вт)' : 'Power (W)',
                   stroke: chartColors.danger,
                   width: 3,
                   fill: chartColors.danger + '20'
                 }
               ]
             };
             
             const u = new uPlot(opts, [x, watts], el);
             charts.w = u;
           }
           
           // Responsive chart resizing
           function onResize() {
             requestAnimationFrame(() => {
               for (const id in charts) {
                 const chartEl = charts[id].root.parentElement;
                 const newWidth = containerWidth(chartEl);
                 charts[id].setSize({ width: newWidth, height: 400 });
               }
             });
           }
           
           // Tab management
           function mountTabs() {
             const tabs = Array.from(document.querySelectorAll('.tab'));
             tabs.forEach(btn => {
               btn.addEventListener('click', () => {
                 // Remove active class from all tabs and content
                 tabs.forEach(b => b.classList.remove('active'));
                 document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                 
                 // Add active class to clicked tab and corresponding content
                 btn.classList.add('active');
                 const id = btn.getAttribute('data-target');
                 const content = document.getElementById(id);
                 if (content) {
                   content.classList.add('active');
                   // Trigger resize for the newly visible chart
                   setTimeout(onResize, 50);
                 }
               });
             });
           }
           
           // Smooth scroll enhancement
           function enhanceScrolling() {
             document.querySelectorAll('a[href^="#"]').forEach(anchor => {
               anchor.addEventListener('click', function (e) {
                 e.preventDefault();
                 const target = document.querySelector(this.getAttribute('href'));
                 if (target) {
                   target.scrollIntoView({
                     behavior: 'smooth',
                     block: 'start'
                   });
                 }
               });
             });
           }
           
           // Intersection observer for animations
           function setupAnimations() {
             const observer = new IntersectionObserver((entries) => {
               entries.forEach(entry => {
                 if (entry.isIntersecting) {
                   entry.target.style.opacity = '1';
                   entry.target.style.transform = 'translateY(0)';
                 }
               });
             }, { threshold: 0.1 });
             
             document.querySelectorAll('.card, .executive-summary').forEach(el => {
               el.style.opacity = '0';
               el.style.transform = 'translateY(20px)';
               el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
               observer.observe(el);
             });
           }
           
           // Initialize everything
           function init() {
             try {
               mkPctChart();
               mkRateChart(); 
               mkVTChart(); 
               mkWChart();
               mountTabs();
               enhanceScrolling();
               setupAnimations();
               animateProgressRing();
               
               // Event listeners
               window.addEventListener('resize', onResize);
               
               // Print handling
               window.addEventListener('beforeprint', () => {
                 document.querySelectorAll('.tab-content').forEach(content => {
                   content.style.display = 'block';
                 });
               });
               
               window.addEventListener('afterprint', () => {
                 document.querySelectorAll('.tab-content:not(.active)').forEach(content => {
                   content.style.display = 'none';
                 });
               });
               
               console.log('Battry report initialized successfully');
             } catch (error) {
               console.error('Error initializing Battry report:', error);
             }
           }
           
           // Start when DOM is ready
           if (document.readyState === 'loading') {
             document.addEventListener('DOMContentLoaded', init);
           } else {
             init();
           }
         </script>
        </body>
        </html>
        """

        // Сохраняем отчет через ReportHistory
        return ReportHistory.shared.addReport(
            htmlContent: html,
            healthScore: result.healthScore,
            dataPoints: history.count
        )
    }

    // Legacy sparkline removed in favor of uPlot interactive charts
}
