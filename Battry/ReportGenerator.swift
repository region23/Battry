import Foundation
import AppKit
import WebKit


/// Генерация HTML‑отчёта с графиками на основе истории и снимка
enum ReportGenerator {
    
    
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
    /// Метаданные генератора нагрузки для отчётов
    struct LoadGeneratorMetadata {
        let wasUsed: Bool
        let profile: String?
        let autoStopReasons: [String]
        
        init(wasUsed: Bool = false, profile: String? = nil, autoStopReasons: [String] = []) {
            self.wasUsed = wasUsed
            self.profile = profile
            self.autoStopReasons = autoStopReasons
        }
    }
    
    /// Создаёт HTML‑отчёт и сохраняет в постоянную директорию (unified method)
    static func generateHTMLContent(result: BatteryAnalysis,
                                    snapshot: BatterySnapshot,
                                    history: [BatteryReading],
                                    calibration: CalibrationResult?,
                                    loadGeneratorMetadata: LoadGeneratorMetadata? = nil,
                                    quickHealthResult: QuickHealthTest.QuickHealthResult? = nil) -> String? {
        
        // Используем специализированные методы в зависимости от типа теста
        if let quickResult = quickHealthResult {
            // Быстрый тест здоровья - используем специализированный отчет
            return generateQuickHealthReport(result: quickResult, batterySnapshot: snapshot)
        } else if let calibResult = calibration {
            // Полный тест калибровки - используем специализированный отчет
            return generateCalibrationReport(
                result: result,
                snapshot: snapshot,
                history: history,
                calibration: calibResult,
                loadGeneratorMetadata: loadGeneratorMetadata
            )
        } else {
            // Обычный отчет без тестов - используем старую логику
            return generateGenericReport(result: result, snapshot: snapshot, history: history)
        }
    }
    
    /// Создаёт обычный HTML‑отчёт без специальных тестов (legacy support)
    private static func generateGenericReport(result: BatteryAnalysis,
                                              snapshot: BatterySnapshot,
                                              history: [BatteryReading]) -> String? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let lang = getReportLanguage()
        let recent = history

        
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
        
        // No calibration section for generic reports

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
        
        // No load generator or quick health sections for generic reports

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


            /* Calibration specific styles */
            .calibration-card {
              border-left: 4px solid var(--accent-primary);
            }
            
            /* Quick Health Test specific styles */
            .quick-health-card {
              border-left: 4px solid var(--success);
              background: linear-gradient(135deg, rgba(16, 185, 129, 0.05) 0%, rgba(16, 185, 129, 0.02) 100%);
            }
            
            .temperature-analysis {
              margin-top: 1.5rem;
              padding: 1rem;
              background: var(--bg-secondary);
              border-radius: 8px;
              border-left: 3px solid var(--warning);
            }
            
            .temperature-analysis h5 {
              color: var(--text-primary);
              margin-bottom: 0.75rem;
              font-size: 1rem;
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

            /* Load Generator Section */
            .load-generator-info {
              margin-top: 1.5rem;
              padding: 1rem;
              background: var(--bg-secondary);
              border-radius: 8px;
              border-left: 3px solid var(--accent-primary);
            }

            .load-generator-info h4 {
              color: var(--text-primary);
              margin-bottom: 0.75rem;
              font-size: 1rem;
            }

            .generator-details > div {
              display: flex;
              justify-content: space-between;
              margin-bottom: 0.5rem;
            }

            .generator-details .label {
              color: var(--text-secondary);
              font-weight: 500;
            }

            .generator-details .value {
              color: var(--text-primary);
              font-weight: 600;
            }

            .auto-stops {
              margin-top: 0.75rem;
            }

            .auto-stops h5 {
              color: var(--text-secondary);
              font-size: 0.9rem;
              margin-bottom: 0.5rem;
            }

            .auto-stops ul {
              list-style: none;
              padding-left: 0;
            }

            .auto-stops li {
              color: var(--warning);
              font-size: 0.85rem;
              margin-bottom: 0.25rem;
              padding-left: 1rem;
              position: relative;
            }

            .auto-stops li::before {
              content: "⚠️";
              position: absolute;
              left: 0;
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

            <!-- Charts Section -->
            <section style="margin: 3rem 0;">
              <div style="text-align: center; margin-bottom: 2rem;">
                <h2 style="font-size: 1.8rem; font-weight: 700; color: var(--text-primary); margin-bottom: 0.5rem;">\(lang == "ru" ? "Детальная аналитика" : "Detailed Analytics")</h2>
                <div style="color: var(--text-secondary); font-size: 1rem;">\(lang == "ru" ? "Графики данных батареи" : "Battery data visualizations")</div>
              </div>
              
              \(generateChargeChart(history: recent, lang: lang))
              \(generateDischargeRateChart(history: recent, lang: lang))
              \(generatePowerChart(history: recent, lang: lang))
              \(generateTemperatureChart(history: recent, lang: lang))
              \(generateDCIRChart(quickHealthResult: nil, lang: lang))
              \(generateOCVChart(history: history, quickHealthResult: nil, lang: lang))
              \(generateEnergyMetricsChart(result: result, snapshot: snapshot, history: recent, quickHealthResult: nil, lang: lang))
            </section>

            <!-- Footer -->
            <footer class=\"footer\">
              <p>\(lang == "ru" ? "Сгенерировано приложением" : "Generated by") <a href=\"https://github.com/region23/Battry\" target=\"_blank\">Battry</a> • \(lang == "ru" ? "Мониторинг состояния батареи macOS" : "macOS Battery Health Monitoring")</p>
            </footer>

          </div>
        </body>
        </html>
        """

        return html
    }
    
    /// Создаёт HTML‑отчёт и сохраняет во временную папку
    static func generateHTML(result: BatteryAnalysis,
                             snapshot: BatterySnapshot,
                             history: [BatteryReading],
                             calibration: CalibrationResult?,
                             quickHealthResult: QuickHealthTest.QuickHealthResult? = nil) -> URL? {
        guard let htmlContent = generateHTMLContent(result: result,
                                                    snapshot: snapshot,
                                                    history: history,
                                                    calibration: calibration,
                                                    quickHealthResult: quickHealthResult) else {
            return nil
        }
        
        // Генерируем имя файла на основе типа теста и даты
        let filename: String
        if let quickResult = quickHealthResult {
            // Для быстрого теста используем дату начала теста
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = formatter.string(from: quickResult.startedAt)
            filename = "Battry_QuickHealth_\(dateString).html"
        } else {
            // Для обычного теста используем текущее время (как было)
            let timestamp = Int(Date().timeIntervalSince1970)
            filename = "Battry_Report_\(timestamp).html"
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let reportURL = tempDir.appendingPathComponent(filename)
        
        do {
            try htmlContent.write(to: reportURL, atomically: true, encoding: .utf8)
            return reportURL
        } catch {
            print("Failed to save report: \(error)")
            return nil
        }
    }
    
    /// Экспорт HTML отчёта в PDF с использованием WKWebView / NSPrintOperation
    static func exportHTMLToPDF(htmlURL: URL, destinationURL: URL, completion: @escaping (Bool) -> Void) {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 1600))
        let request = URLRequest(url: htmlURL)
        final class NavDelegate: NSObject, WKNavigationDelegate {
            let dest: URL
            let completion: (Bool) -> Void
            init(dest: URL, completion: @escaping (Bool) -> Void) { self.dest = dest; self.completion = completion }
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                if #available(macOS 11.0, *) {
                    let config = WKPDFConfiguration()
                    webView.createPDF(configuration: config) { result in
                        switch result {
                        case .success(let data):
                            do { try data.write(to: self.dest, options: .atomic); self.completion(true) } catch { self.completion(false) }
                        case .failure(_):
                            self.completion(false)
                        }
                    }
                } else {
                    let printInfo = NSPrintInfo.shared
                    printInfo.jobDisposition = NSPrintInfo.JobDisposition.save
                    printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = dest
                    let op = NSPrintOperation(view: webView, printInfo: printInfo)
                    op.showsPrintPanel = false
                    op.showsProgressPanel = false
                    let ok = op.run()
                    completion(ok)
                }
            }
        }
        let delegate = NavDelegate(dest: destinationURL, completion: completion)
        webView.navigationDelegate = delegate
        webView.load(request)
        // Retain delegate until completion
        objc_setAssociatedObject(webView, UnsafeRawPointer(bitPattern: 0xBEEFBEEF)!, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    // MARK: - SVG Chart Generation
    
    /// Generates SVG chart for battery charge level over time
    private static func generateChargeChart(history: [BatteryReading], width: Int = 800, height: Int = 300, lang: String) -> String {
        guard !history.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных об уровне заряда" : "No battery charge data available")</div>"
        }
        
        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20
        
        // Find data bounds
        let timestamps = history.map { $0.timestamp.timeIntervalSince1970 }
        let minTime = timestamps.min() ?? 0
        let maxTime = timestamps.max() ?? 1
        let timeRange = max(maxTime - minTime, 1)
        
        // Generate SVG path for charge line
        var pathCommands: [String] = []
        var chargingBands: [String] = []
        
        for (index, reading) in history.enumerated() {
            let x = Double(chartWidth) * (reading.timestamp.timeIntervalSince1970 - minTime) / timeRange
            let y = Double(chartHeight) * (1.0 - Double(reading.percentage) / 100.0)
            
            if index == 0 {
                pathCommands.append("M\(Int(x + Double(marginLeft))),\(Int(y + Double(marginTop)))")
            } else {
                pathCommands.append("L\(Int(x + Double(marginLeft))),\(Int(y + Double(marginTop)))")
            }
            
            // Track charging periods for background bands
            if reading.isCharging {
                let bandX = Int(x + Double(marginLeft))
                chargingBands.append("<rect x=\"\(bandX-1)\" y=\"\(marginTop)\" width=\"2\" height=\"\(chartHeight)\" fill=\"rgba(16, 185, 129, 0.2)\" />")
            }
        }
        
        let pathData = pathCommands.joined(separator: " ")
        
        // Create time axis labels
        let timeLabels = generateTimeLabels(minTime: minTime, maxTime: maxTime, width: chartWidth, marginLeft: marginLeft, marginTop: marginTop, chartHeight: chartHeight, lang: lang)
        
        // Create percentage axis labels
        let percentageLabels = generatePercentageLabels(chartHeight: chartHeight, marginLeft: marginLeft, marginTop: marginTop, lang: lang)
        
        return """
        <div class="svg-chart-container" style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);">
          <div class="chart-header" style="margin-bottom: 1rem; text-align: center;">
            <div class="chart-title" style="font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;">\(lang == "ru" ? "Уровень заряда батареи" : "Battery Charge Level")</div>
            <div class="chart-subtitle" style="color: var(--text-muted); font-size: 0.9rem;">\(lang == "ru" ? "Процент заряда во времени с периодами зарядки" : "Charge percentage over time with charging periods")</div>
          </div>
          <svg viewBox="0 0 \(width) \(height)" style="width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;">
            <!-- Grid lines -->
            <defs>
              <pattern id="grid" width="40" height="30" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 30" fill="none" stroke="var(--border-subtle)" stroke-width="0.5"/>
              </pattern>
            </defs>
            <rect x="\(marginLeft)" y="\(marginTop)" width="\(chartWidth)" height="\(chartHeight)" fill="url(#grid)" opacity="0.3"/>
            
            <!-- Charging periods background -->
            \(chargingBands.joined(separator: "\n            "))
            
            <!-- Charge line and micro-drop markers -->
            <path d="\(pathData)" fill="none" stroke="var(--accent-primary)" stroke-width="2.5" opacity="0.9"/>
            \(generateMicroDropMarkers(history: history, minTime: minTime, timeRange: timeRange, marginLeft: marginLeft, marginTop: marginTop, chartWidth: chartWidth, chartHeight: chartHeight))
            
            <!-- Axes -->
            <line x1="\(marginLeft)" y1="\(marginTop)" x2="\(marginLeft)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            <line x1="\(marginLeft)" y1="\(marginTop + chartHeight)" x2="\(marginLeft + chartWidth)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            
            <!-- Axis labels -->
            \(timeLabels)
            \(percentageLabels)
          </svg>
        </div>
        """
    }
    
    /// Generates SVG chart for discharge rate over time
    private static func generateDischargeRateChart(history: [BatteryReading], width: Int = 800, height: Int = 300, lang: String) -> String {
        guard history.count > 1 else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Недостаточно данных для расчета скорости разряда" : "Insufficient data for discharge rate calculation")</div>"
        }
        
        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20
        
        // Calculate discharge rates
        var dischargeRates: [(timestamp: Double, rate: Double)] = []
        
        for i in 1..<history.count {
            let prev = history[i-1]
            let curr = history[i]
            
            if prev.isOnBattery && curr.isOnBattery {
                let timeDiff = curr.timestamp.timeIntervalSince(prev.timestamp) / 3600.0 // hours
                if timeDiff > 0 && timeDiff < 2 { // Only consider reasonable time intervals
                    let percentageDiff = Double(prev.percentage - curr.percentage)
                    if percentageDiff > 0 {
                        let rate = percentageDiff / timeDiff
                        dischargeRates.append((timestamp: curr.timestamp.timeIntervalSince1970, rate: rate))
                    }
                }
            }
        }
        
        guard !dischargeRates.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных о скорости разряда" : "No discharge rate data available")</div>"
        }
        
        let timestamps = dischargeRates.map { $0.timestamp }
        let rates = dischargeRates.map { $0.rate }
        let minTime = timestamps.min() ?? 0
        let maxTime = timestamps.max() ?? 1
        let timeRange = max(maxTime - minTime, 1)
        let maxRate = rates.max() ?? 10
        
        // Generate SVG path
        var pathCommands: [String] = []
        
        for (index, dataPoint) in dischargeRates.enumerated() {
            let x = Double(chartWidth) * (dataPoint.timestamp - minTime) / timeRange
            let y = Double(chartHeight) * (1.0 - dataPoint.rate / maxRate)
            
            if index == 0 {
                pathCommands.append("M\(Int(x + Double(marginLeft))),\(Int(y + Double(marginTop)))")
            } else {
                pathCommands.append("L\(Int(x + Double(marginLeft))),\(Int(y + Double(marginTop)))")
            }
        }
        
        let pathData = pathCommands.joined(separator: " ")
        let timeLabels = generateTimeLabels(minTime: minTime, maxTime: maxTime, width: chartWidth, marginLeft: marginLeft, marginTop: marginTop, chartHeight: chartHeight, lang: lang)
        let rateLabels = generateRateLabels(maxRate: maxRate, chartHeight: chartHeight, marginLeft: marginLeft, marginTop: marginTop, lang: lang)
        
        return """
        <div class="svg-chart-container" style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);">
          <div class="chart-header" style="margin-bottom: 1rem; text-align: center;">
            <div class="chart-title" style="font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;">\(lang == "ru" ? "Скорость разряда" : "Discharge Rate")</div>
            <div class="chart-subtitle" style="color: var(--text-muted); font-size: 0.9rem;">\(lang == "ru" ? "Скорость разряда в процентах за час" : "Discharge rate in percent per hour")</div>
          </div>
          <svg viewBox="0 0 \(width) \(height)" style="width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;">
            <!-- Grid lines -->
            <defs>
              <pattern id="grid2" width="40" height="30" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 30" fill="none" stroke="var(--border-subtle)" stroke-width="0.5"/>
              </pattern>
            </defs>
            <rect x="\(marginLeft)" y="\(marginTop)" width="\(chartWidth)" height="\(chartHeight)" fill="url(#grid2)" opacity="0.3"/>
            
            <!-- Discharge rate line -->
            <path d="\(pathData)" fill="none" stroke="var(--accent-secondary)" stroke-width="2.5" opacity="0.9"/>
            \(generateMicroDropMarkers(history: history, minTime: minTime, timeRange: timeRange, marginLeft: marginLeft, marginTop: marginTop, chartWidth: chartWidth, chartHeight: chartHeight))
            
            <!-- Axes -->
            <line x1="\(marginLeft)" y1="\(marginTop)" x2="\(marginLeft)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            <line x1="\(marginLeft)" y1="\(marginTop + chartHeight)" x2="\(marginLeft + chartWidth)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            
            <!-- Axis labels -->
            \(timeLabels)
            \(rateLabels)
          </svg>
        </div>
        """
    }

    /// Generates Power vs Time chart
    private static func generatePowerChart(history: [BatteryReading], width: Int = 800, height: Int = 300, lang: String) -> String {
        guard !history.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных мощности" : "No power data available")</div>"
        }
        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20
        let timestamps = history.map { $0.timestamp.timeIntervalSince1970 }
        let minTime = timestamps.min() ?? 0
        let maxTime = timestamps.max() ?? 1
        let timeRange = max(maxTime - minTime, 1)
        let powers = history.map { abs($0.power) }
        let maxPower = max(1.0, powers.max() ?? 1.0)
        var pathCommands: [String] = []
        for (idx, r) in history.enumerated() {
            let x = Double(chartWidth) * (r.timestamp.timeIntervalSince1970 - minTime) / timeRange
            let y = Double(chartHeight) * (1.0 - abs(r.power) / maxPower)
            let svgX = Int(x + Double(marginLeft))
            let svgY = Int(y + Double(marginTop))
            if idx == 0 { pathCommands.append("M\(svgX),\(svgY)") } else { pathCommands.append("L\(svgX),\(svgY)") }
        }
        let pathData = pathCommands.joined(separator: " ")
        return """
        <div class=\"svg-chart-container\" style=\"background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);\">
          <div class=\"chart-header\" style=\"margin-bottom: 1rem; text-align: center;\">
            <div class=\"chart-title\" style=\"font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;\">\(lang == "ru" ? "Мощность во времени" : "Power over time")</div>
            <div class=\"chart-subtitle\" style=\"color: var(--text-muted); font-size: 0.9rem;\">\(lang == "ru" ? "P = V × I" : "P = V × I")</div>
          </div>
          <svg viewBox=\"0 0 \(width) \(height)\" style=\"width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;\">
            <defs><pattern id=\"gridP\" width=\"40\" height=\"30\" patternUnits=\"userSpaceOnUse\"><path d=\"M 40 0 L 0 0 0 30\" fill=\"none\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\"/></pattern></defs>
            <rect x=\"\(marginLeft)\" y=\"\(marginTop)\" width=\"\(chartWidth)\" height=\"\(chartHeight)\" fill=\"url(#gridP)\" opacity=\"0.3\"/>
            <path d=\"\(pathData)\" fill=\"none\" stroke=\"var(--accent-primary)\" stroke-width=\"2.5\" opacity=\"0.9\"/>
          </svg>
        </div>
        """
    }

    /// Generates Temperature vs Time chart
    private static func generateTemperatureChart(history: [BatteryReading], width: Int = 800, height: Int = 300, lang: String) -> String {
        guard !history.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных температуры" : "No temperature data available")</div>"
        }
        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20
        let timestamps = history.map { $0.timestamp.timeIntervalSince1970 }
        let minTime = timestamps.min() ?? 0
        let maxTime = timestamps.max() ?? 1
        let timeRange = max(maxTime - minTime, 1)
        let temps = history.map { $0.temperature }
        let minTemp = temps.min() ?? 20
        let maxTemp = max(minTemp + 1, temps.max() ?? 40)
        var pathCommands: [String] = []
        for (idx, r) in history.enumerated() {
            let x = Double(chartWidth) * (r.timestamp.timeIntervalSince1970 - minTime) / timeRange
            let y = Double(chartHeight) * (1.0 - (r.temperature - minTemp) / (maxTemp - minTemp))
            let svgX = Int(x + Double(marginLeft))
            let svgY = Int(y + Double(marginTop))
            if idx == 0 { pathCommands.append("M\(svgX),\(svgY)") } else { pathCommands.append("L\(svgX),\(svgY)") }
        }
        let pathData = pathCommands.joined(separator: " ")
        return """
        <div class=\"svg-chart-container\" style=\"background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);\">
          <div class=\"chart-header\" style=\"margin-bottom: 1rem; text-align: center;\">
            <div class=\"chart-title\" style=\"font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;\">\(lang == "ru" ? "Температура во времени" : "Temperature over time")</div>
          </div>
          <svg viewBox=\"0 0 \(width) \(height)\" style=\"width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;\">
            <defs><pattern id=\"gridT\" width=\"40\" height=\"30\" patternUnits=\"userSpaceOnUse\"><path d=\"M 40 0 L 0 0 0 30\" fill=\"none\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\"/></pattern></defs>
            <rect x=\"\(marginLeft)\" y=\"\(marginTop)\" width=\"\(chartWidth)\" height=\"\(chartHeight)\" fill=\"url(#gridT)\" opacity=\"0.3\"/>
            <path d=\"\(pathData)\" fill=\"none\" stroke=\"var(--warning)\" stroke-width=\"2.5\" opacity=\"0.9\"/>
          </svg>
        </div>
        """
    }

    /// Micro-drop markers for SOC chart
    private static func generateMicroDropMarkers(history: [BatteryReading], minTime: Double, timeRange: Double, marginLeft: Int, marginTop: Int, chartWidth: Int, chartHeight: Int) -> String {
        guard history.count >= 2 else { return "" }
        var markers: [String] = []
        for i in 1..<history.count {
            let prev = history[i-1]
            let cur = history[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
            let d = prev.percentage - cur.percentage
            if prev.isOnBattery && cur.isOnBattery && dt <= 120 && d >= 2 {
                let x = Int(Double(marginLeft) + (Double((cur.timestamp.timeIntervalSince1970 - minTime) / timeRange) * Double(chartWidth)))
                let y = Int(Double(marginTop) + Double(chartHeight) * (1.0 - Double(cur.percentage) / 100.0))
                markers.append("<circle cx=\"\(x)\" cy=\"\(y)\" r=\"4\" fill=\"var(--danger)\" stroke=\"white\" stroke-width=\"1.5\"/>")
            }
        }
        return markers.joined(separator: "\n            ")
    }
    
    /// Generates time axis labels for charts
    private static func generateTimeLabels(minTime: Double, maxTime: Double, width: Int, marginLeft: Int, marginTop: Int, chartHeight: Int, lang: String) -> String {
        let timeRange = maxTime - minTime
        let numberOfLabels = 5
        let labelInterval = timeRange / Double(numberOfLabels - 1)
        
        var labels: [String] = []
        
        for i in 0..<numberOfLabels {
            let timestamp = minTime + Double(i) * labelInterval
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeLabel = formatter.string(from: date)
            
            let x = Int(Double(width) * Double(i) / Double(numberOfLabels - 1)) + marginLeft
            let y = marginTop + chartHeight + 15
            
            labels.append("<text x=\"\(x)\" y=\"\(y)\" text-anchor=\"middle\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(timeLabel)</text>")
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    /// Generates percentage axis labels for charge chart
    private static func generatePercentageLabels(chartHeight: Int, marginLeft: Int, marginTop: Int, lang: String) -> String {
        var labels: [String] = []
        
        for percentage in stride(from: 0, through: 100, by: 25) {
            let y = marginTop + Int(Double(chartHeight) * (1.0 - Double(percentage) / 100.0))
            labels.append("<text x=\"\(marginLeft - 8)\" y=\"\(y + 4)\" text-anchor=\"end\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(percentage)%</text>")
            
            // Grid line
            labels.append("<line x1=\"\(marginLeft)\" y1=\"\(y)\" x2=\"\(marginLeft + 750)\" y2=\"\(y)\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\" opacity=\"0.5\"/>")
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    /// Generates rate axis labels for discharge rate chart
    private static func generateRateLabels(maxRate: Double, chartHeight: Int, marginLeft: Int, marginTop: Int, lang: String) -> String {
        var labels: [String] = []
        let steps = 5
        
        for i in 0...steps {
            let rate = maxRate * Double(i) / Double(steps)
            let y = marginTop + Int(Double(chartHeight) * (1.0 - Double(i) / Double(steps)))
            let rateText = String(format: "%.1f", rate) + (lang == "ru" ? " %/ч" : " %/h")
            
            labels.append("<text x=\"\(marginLeft - 8)\" y=\"\(y + 4)\" text-anchor=\"end\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(rateText)</text>")
            
            // Grid line
            if i > 0 {
                labels.append("<line x1=\"\(marginLeft)\" y1=\"\(y)\" x2=\"\(marginLeft + 750)\" y2=\"\(y)\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\" opacity=\"0.5\"/>")
            }
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    /// Generates DCIR chart from QuickHealthTest results
    private static func generateDCIRChart(quickHealthResult: QuickHealthTest.QuickHealthResult?, width: Int = 800, height: Int = 300, lang: String) -> String {
        guard let qhr = quickHealthResult, !qhr.dcirPoints.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных DCIR для отображения" : "No DCIR data available for display")</div>"
        }
        
        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20
        
        // Prepare DCIR data points
        let dcirPoints = qhr.dcirPoints.sorted { $0.socPercent > $1.socPercent }
        let socValues = dcirPoints.map { $0.socPercent }
        let dcirValues = dcirPoints.map { $0.resistanceMohm }
        
        let minSOC = socValues.min() ?? 0
        let maxSOC = socValues.max() ?? 100
        let socRange = max(maxSOC - minSOC, 1)
        
        let maxDCIR = dcirValues.max() ?? 100
        
        // Generate SVG path for DCIR line
        var pathCommands: [String] = []
        var dataPoints: [String] = []
        
        for point in dcirPoints {
            let x = Double(chartWidth) * (point.socPercent - minSOC) / socRange
            let y = Double(chartHeight) * (1.0 - point.resistanceMohm / maxDCIR)
            
            let svgX = Int(x + Double(marginLeft))
            let svgY = Int(y + Double(marginTop))
            
            if pathCommands.isEmpty {
                pathCommands.append("M\(svgX),\(svgY)")
            } else {
                pathCommands.append("L\(svgX),\(svgY)")
            }
            
            // Add data point circle
            dataPoints.append("<circle cx=\"\(svgX)\" cy=\"\(svgY)\" r=\"4\" fill=\"var(--accent-primary)\" stroke=\"white\" stroke-width=\"2\"/>")
        }
        
        let pathData = pathCommands.joined(separator: " ")
        
        // Create SOC axis labels
        let socLabels = generateSOCLabels(minSOC: minSOC, maxSOC: maxSOC, chartWidth: chartWidth, marginLeft: marginLeft, marginTop: marginTop, chartHeight: chartHeight, lang: lang)
        
        // Create DCIR axis labels
        let dcirAxisLabels = generateDCIRLabels(maxDCIR: maxDCIR, chartHeight: chartHeight, marginLeft: marginLeft, marginTop: marginTop, lang: lang)
        
        return """
        <div class="svg-chart-container" style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);">
          <div class="chart-header" style="margin-bottom: 1rem; text-align: center;">
            <div class="chart-title" style="font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;">\(lang == "ru" ? "Внутреннее сопротивление (DCIR)" : "Internal Resistance (DCIR)")</div>
            <div class="chart-subtitle" style="color: var(--text-muted); font-size: 0.9rem;">\(lang == "ru" ? "Сопротивление батареи на разных уровнях заряда" : "Battery resistance at different charge levels")</div>
          </div>
          <svg viewBox="0 0 \(width) \(height)" style="width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;">
            <!-- Grid lines -->
            <defs>
              <pattern id="dcir-grid" width="40" height="30" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 30" fill="none" stroke="var(--border-subtle)" stroke-width="0.5"/>
              </pattern>
            </defs>
            <rect x="\(marginLeft)" y="\(marginTop)" width="\(chartWidth)" height="\(chartHeight)" fill="url(#dcir-grid)" opacity="0.3"/>
            
            <!-- DCIR line -->
            <path d="\(pathData)" fill="none" stroke="var(--danger)" stroke-width="2.5" opacity="0.9"/>
            
            <!-- Data points -->
            \(dataPoints.joined(separator: "\n            "))
            
            <!-- Axes -->
            <line x1="\(marginLeft)" y1="\(marginTop)" x2="\(marginLeft)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            <line x1="\(marginLeft)" y1="\(marginTop + chartHeight)" x2="\(marginLeft + chartWidth)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            
            <!-- Axis labels -->
            \(socLabels)
            \(dcirAxisLabels)
          </svg>
        </div>
        """
    }
    
    /// Generates OCV curve chart
    private static func generateOCVChart(history: [BatteryReading], quickHealthResult: QuickHealthTest.QuickHealthResult?, width: Int = 800, height: Int = 300, lang: String) -> String {
        let dcirPoints = quickHealthResult?.dcirPoints ?? []
        let ocvAnalyzer = OCVAnalyzer(dcirPoints: dcirPoints)
        let ocvCurve = ocvAnalyzer.buildOCVCurve(from: history, binSize: 2.0)
        let kneeSOC = quickHealthResult?.kneeSOC ?? OCVAnalyzer.findKneeSOC(in: ocvCurve)

        guard !ocvCurve.isEmpty else {
            return "<div style=\"padding: 2rem; text-align: center; color: #666;\">\(lang == "ru" ? "Нет данных OCV для отображения" : "No OCV data available for display")</div>"
        }

        let chartWidth = width - 80
        let chartHeight = height - 80
        let marginLeft = 50
        let marginTop = 20

        let minVoltage = ocvCurve.map { $0.ocvVoltage }.min() ?? 10.0
        let maxVoltage = ocvCurve.map { $0.ocvVoltage }.max() ?? 13.0
        let voltageRange = max(0.1, maxVoltage - minVoltage)

        var pathCommands: [String] = []
        var kneeMarker = ""
        for (index, point) in ocvCurve.enumerated() {
            let x = Double(chartWidth) * (point.socPercent / 100.0)
            let y = Double(chartHeight) * (1.0 - (point.ocvVoltage - minVoltage) / voltageRange)
            let svgX = Int(x + Double(marginLeft))
            let svgY = Int(y + Double(marginTop))
            if index == 0 { pathCommands.append("M\(svgX),\(svgY)") } else { pathCommands.append("L\(svgX),\(svgY)") }
            if let k = kneeSOC, abs(point.socPercent - k) < 1.0 {
                kneeMarker = """
                <circle cx=\"\(svgX)\" cy=\"\(svgY)\" r=\"6\" fill=\"var(--danger)\" stroke=\"white\" stroke-width=\"3\"/>
                <text x=\"\(svgX + 15)\" y=\"\(svgY - 10)\" fill=\"var(--danger)\" font-size=\"11px\" font-weight=\"600\">\(lang == "ru" ? "Колено" : "Knee")</text>
                """
            }
        }
        let pathData = pathCommands.joined(separator: " ")

        return """
        <div class="svg-chart-container" style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);">
          <div class="chart-header" style="margin-bottom: 1rem; text-align: center;">
            <div class="chart-title" style="font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;">\(lang == "ru" ? "Кривая напряжения холостого хода (OCV)" : "Open Circuit Voltage (OCV) Curve")</div>
            <div class="chart-subtitle" style="color: var(--text-muted); font-size: 0.9rem;">\(lang == "ru" ? "Компенсированная кривая V_OC(SOC) из данных теста" : "Compensated V_OC(SOC) curve from test data")</div>
          </div>
          <svg viewBox="0 0 \(width) \(height)" style="width: 100%; height: auto; font-family: system-ui, sans-serif; font-size: 12px;">
            <defs>
              <pattern id="ocv-grid" width="40" height="30" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 30" fill="none" stroke="var(--border-subtle)" stroke-width="0.5"/>
              </pattern>
            </defs>
            <rect x="\(marginLeft)" y="\(marginTop)" width="\(chartWidth)" height="\(chartHeight)" fill="url(#ocv-grid)" opacity="0.3"/>
            <path d="\(pathData)" fill="none" stroke="var(--accent-secondary)" stroke-width="3" opacity="0.9"/>
            \(kneeMarker)
            <line x1="\(marginLeft)" y1="\(marginTop)" x2="\(marginLeft)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            <line x1="\(marginLeft)" y1="\(marginTop + chartHeight)" x2="\(marginLeft + chartWidth)" y2="\(marginTop + chartHeight)" stroke="var(--border-default)" stroke-width="1"/>
            \(generatePercentageLabels(chartHeight: chartHeight, marginLeft: marginLeft, marginTop: marginTop, lang: lang))
            \(generateVoltageLabels(minVoltage: minVoltage, maxVoltage: maxVoltage, chartHeight: chartHeight, marginLeft: marginLeft, marginTop: marginTop, lang: lang))
          </svg>
        </div>
        """
    }
    
    /// Helper functions for energy metrics chart generation
    private static func runtimeForecastsHHMM(designWh: Double, effectiveWh: Double) -> (f0: String, f1: String, f2: String) {
        func one(_ cRate: Double) -> String {
            guard designWh > 0, effectiveWh > 0 else { return "—" }
            let targetW = designWh * cRate
            guard targetW > 0 else { return "—" }
            let hours = effectiveWh / targetW
            return formatHoursMinutes(hours: hours)
        }
        return (one(0.1), one(0.2), one(0.3))
    }
    
    /// Formats hours as HH:MM (zero-padded minutes)
    private static func formatHoursMinutes(hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d", h, m)
    }
    
    /// Generates energy metrics chart
    private static func generateEnergyMetricsChart(result: BatteryAnalysis, snapshot: BatterySnapshot, history: [BatteryReading], quickHealthResult: QuickHealthTest.QuickHealthResult?, width: Int = 800, height: Int = 300, lang: String) -> String {
        // Create a combined energy metrics visualization
        let sohEnergy = quickHealthResult?.sohEnergy ?? result.sohEnergy
        let averagePower = quickHealthResult?.averagePower ?? result.averagePower
        let targetPower = quickHealthResult?.targetPower ?? 10.0
        let powerQuality = quickHealthResult?.powerControlQuality ?? 100.0
        // Runtime forecasts for equivalent low/medium/high workload presets
        let avgVOC = OCVAnalyzer.averageVOC(from: history, dcirPoints: quickHealthResult?.dcirPoints ?? []) ?? 11.1
        let designWh = Double(max(0, snapshot.designCapacity)) * max(5.0, avgVOC) / 1000.0
        let effectiveWh = designWh * max(0.0, min(1.0, sohEnergy / 100.0))
        let forecasts = runtimeForecastsHHMM(designWh: designWh, effectiveWh: effectiveWh)
        let energyWindowLabel = quickHealthResult?.energyWindowDisplayLabel ?? "80→65%"
        let energyWindowStatus = quickHealthResult?.energyEstimateIsProvisional == true
            ? (lang == "ru" ? "Неполное окно — оценка предварительная" : "Partial window - provisional estimate")
            : (lang == "ru" ? "Измеренное окно" : "Measured window")
        
        return """
        <div class="svg-chart-container" style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: 1rem; padding: 1.5rem; margin: 1rem 0; box-shadow: var(--shadow-md);">
          <div class="chart-header" style="margin-bottom: 1rem; text-align: center;">
            <div class="chart-title" style="font-size: 1.1rem; font-weight: 600; color: var(--text-primary); margin-bottom: 0.25rem;">\(lang == "ru" ? "Энергетические характеристики" : "Energy Performance")</div>
            <div class="chart-subtitle" style="color: var(--text-muted); font-size: 0.9rem;">\(lang == "ru" ? "Анализ энергоотдачи и качества CP-контроля" : "Energy delivery analysis and CP control quality")</div>
          </div>
          
          <div class="energy-metrics-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">
            <div class="energy-metric" style="text-align: center; padding: 1rem; background: var(--bg-secondary); border-radius: 0.75rem;">
              <div style="font-size: 2rem; font-weight: 800; color: var(--success);">\(String(format: "%.1f", sohEnergy))%</div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.25rem;">\(lang == "ru" ? "SOH по энергии" : "SOH Energy")</div>
              <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.25rem;">\(lang == "ru" ? "Реальная энергоотдача" : "Actual energy delivery")</div>
            </div>
            
            <div class="energy-metric" style="text-align: center; padding: 1rem; background: var(--bg-secondary); border-radius: 0.75rem;">
              <div style="font-size: 2rem; font-weight: 800; color: var(--accent-primary);">\(String(format: "%.1f", averagePower))W</div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.25rem;">\(lang == "ru" ? "Средняя мощность" : "Average Power")</div>
              <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.25rem;">\(lang == "ru" ? "Цель: \(String(format: "%.1f", targetPower))W" : "Target: \(String(format: "%.1f", targetPower))W")</div>
            </div>
            
            <div class="energy-metric" style="text-align: center; padding: 1rem; background: var(--bg-secondary); border-radius: 0.75rem;">
              <div style="font-size: 2rem; font-weight: 800; color: var(--warning);">\(String(format: "%.0f", powerQuality))%</div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.25rem;">\(lang == "ru" ? "Качество CP" : "CP Quality")</div>
              <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.25rem;">\(lang == "ru" ? "Стабильность мощности" : "Power stability")</div>
            </div>
            
            <div class="energy-metric" style="text-align: center; padding: 1rem; background: var(--bg-secondary); border-radius: 0.75rem;">
              <div style="font-size: 2rem; font-weight: 800; color: var(--accent-secondary);">\(String(format: "%.1f", quickHealthResult?.energyDelivered80to50Wh ?? 0))Wh</div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.25rem;">\(lang == "ru" ? "Энергия \(energyWindowLabel)" : "Energy \(energyWindowLabel)")</div>
              <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.25rem;">\(energyWindowStatus)</div>
            </div>
            
            <div class="energy-metric" style="text-align: left; padding: 1rem; background: var(--bg-secondary); border-radius: 0.75rem;">
              <div style="font-size: 1.1rem; font-weight: 700; color: var(--text-primary);">\(lang == "ru" ? "Прогноз автономности (эквивалентные нагрузки)" : "Runtime Forecast (Equivalent workloads)")</div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.25rem;">\(lang == "ru" ? "Легкая экв.:" : "Light eq.:") <strong>\(forecasts.f0)</strong></div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.2rem;">\(lang == "ru" ? "Средняя экв.:" : "Medium eq.:") <strong>\(forecasts.f1)</strong></div>
              <div style="font-size: 0.9rem; color: var(--text-secondary); margin-top: 0.2rem;">\(lang == "ru" ? "Тяжелая экв.:" : "Heavy eq.:") <strong>\(forecasts.f2)</strong></div>
            </div>
          </div>
        </div>
        """
    }
    
    private static func generateSOCLabels(minSOC: Double, maxSOC: Double, chartWidth: Int, marginLeft: Int, marginTop: Int, chartHeight: Int, lang: String) -> String {
        var labels: [String] = []
        let socRange = maxSOC - minSOC
        let numberOfLabels = 5
        
        for i in 0..<numberOfLabels {
            let soc = minSOC + (socRange * Double(i) / Double(numberOfLabels - 1))
            let x = Int(Double(chartWidth) * Double(i) / Double(numberOfLabels - 1)) + marginLeft
            let y = marginTop + chartHeight + 15
            
            labels.append("<text x=\"\(x)\" y=\"\(y)\" text-anchor=\"middle\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(Int(soc))%</text>")
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    private static func generateDCIRLabels(maxDCIR: Double, chartHeight: Int, marginLeft: Int, marginTop: Int, lang: String) -> String {
        var labels: [String] = []
        let steps = 5
        
        for i in 0...steps {
            let dcir = maxDCIR * Double(i) / Double(steps)
            let y = marginTop + Int(Double(chartHeight) * (1.0 - Double(i) / Double(steps)))
            let dcirText = String(format: "%.0f", dcir) + (lang == "ru" ? " мОм" : " mΩ")
            
            labels.append("<text x=\"\(marginLeft - 8)\" y=\"\(y + 4)\" text-anchor=\"end\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(dcirText)</text>")
            
            if i > 0 {
                labels.append("<line x1=\"\(marginLeft)\" y1=\"\(y)\" x2=\"\(marginLeft + 750)\" y2=\"\(y)\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\" opacity=\"0.5\"/>")
            }
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    private static func generateVoltageLabels(minVoltage: Double, maxVoltage: Double, chartHeight: Int, marginLeft: Int, marginTop: Int, lang: String) -> String {
        var labels: [String] = []
        let steps = 5
        let voltageRange = maxVoltage - minVoltage
        
        for i in 0...steps {
            let voltage = minVoltage + (voltageRange * Double(i) / Double(steps))
            let y = marginTop + Int(Double(chartHeight) * (1.0 - Double(i) / Double(steps)))
            let voltageText = String(format: "%.1fV", voltage)
            
            labels.append("<text x=\"\(marginLeft - 8)\" y=\"\(y + 4)\" text-anchor=\"end\" fill=\"var(--text-secondary)\" font-size=\"10px\">\(voltageText)</text>")
            
            if i > 0 {
                labels.append("<line x1=\"\(marginLeft)\" y1=\"\(y)\" x2=\"\(marginLeft + 750)\" y2=\"\(y)\" stroke=\"var(--border-subtle)\" stroke-width=\"0.5\" opacity=\"0.5\"/>")
            }
        }
        
        return labels.joined(separator: "\n            ")
    }
    
    // MARK: - Specialized Report Generation
    
    /// Создаёт специализированный HTML‑отчёт для полного теста калибровки
    static func generateCalibrationReport(
        result: BatteryAnalysis,
        snapshot: BatterySnapshot,
        history: [BatteryReading],
        calibration: CalibrationResult,
        loadGeneratorMetadata: LoadGeneratorMetadata? = nil
    ) -> String? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let lang = getReportLanguage()
        let recent = history
        
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
        
        // Generate calibration section
        let startDateStr = df.string(from: calibration.startedAt)
        let endDateStr = df.string(from: calibration.finishedAt)
        let durationStr = String(format: "%.1f", calibration.durationHours)
        let avgDischargeStr = String(format: "%.1f", calibration.avgDischargePerHour)
        let runtimeStr = String(format: "%.1f", calibration.estimatedRuntimeFrom100To0Hours)
        
        // Prepare formatted values
        let wearText = String(format: "%.0f%%", snapshot.wearPercent)
        let avgDisText = String(format: "%.1f", result.avgDischargePerHour)
        let trendDisText = String(format: "%.1f", result.trendDischargePerHour)
        let runtimeText = String(format: "%.1f", result.estimatedRuntimeFrom100To0Hours)
        
        // Generate load generator metadata section
        let loadGeneratorHTML: String = {
            guard let metadata = loadGeneratorMetadata, metadata.wasUsed else { return "" }
            let title = lang == "ru" ? "Генератор нагрузки" : "Load Generator"
            let profileText = metadata.profile ?? (lang == "ru" ? "Неизвестно" : "Unknown")
            
            var autoStopsHTML = ""
            if !metadata.autoStopReasons.isEmpty {
                let autoStopsTitle = lang == "ru" ? "Автостопы:" : "Auto-stops:"
                let stopItems = metadata.autoStopReasons.map { "<li>\($0)</li>" }.joined()
                autoStopsHTML = """
                <div class="auto-stops">
                  <h5>\(autoStopsTitle)</h5>
                  <ul>\(stopItems)</ul>
                </div>
                """
            }
            
            return """
            <div class="card">
              <div class="card-header">
                <div class="card-icon">⚙️</div>
                <h3>\(title)</h3>
              </div>
              <div class="card-content">
                <div class="detail-row">
                  <span class="label">\(lang == "ru" ? "Профиль:" : "Profile:")</span>
                  <span class="value">\(profileText)</span>
                </div>
                \(autoStopsHTML)
              </div>
            </div>
            """
        }()
        
        let html = """
        <!doctype html>
        <html lang=\"\(lang)\">
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, user-scalable=yes\">
          <title>Battry • \(lang == "ru" ? "Отчёт о калибровке батареи" : "Battery Calibration Report")</title>
          <meta name=\"description\" content=\"\(lang == "ru" ? "Подробный отчёт о калибровке батареи MacBook" : "Detailed MacBook battery calibration report")\">
          <style>
            /* CSS Custom Properties with Dark/Light Theme */
            :root {
              /* Light theme colors */
              --bg-primary: #ffffff;
              --bg-secondary: #f8fafc;
              --bg-card: #ffffff;
              --text-primary: #1e293b;
              --text-secondary: #475569;
              --text-muted: #64748b;
              --border-subtle: #e2e8f0;
              --border-light: #f1f5f9;
              --accent-primary: #0ea5e9;
              --accent-secondary: #8b5cf6;
              --success: #10b981;
              --warning: #f59e0b;
              --danger: #ef4444;
              --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
              --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
              --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
            }
            
            @media (prefers-color-scheme: dark) {
              :root {
                --bg-primary: #0f172a;
                --bg-secondary: #1e293b;
                --bg-card: #1e293b;
                --text-primary: #f1f5f9;
                --text-secondary: #cbd5e1;
                --text-muted: #94a3b8;
                --border-subtle: #334155;
                --border-light: #475569;
                --accent-primary: #38bdf8;
                --accent-secondary: #a78bfa;
                --success: #34d399;
                --warning: #fbbf24;
                --danger: #f87171;
              }
            }
            
            * {
              margin: 0;
              padding: 0;
              box-sizing: border-box;
            }
            
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              background: var(--bg-primary);
              color: var(--text-primary);
              line-height: 1.6;
              font-size: 14px;
            }
            
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 2rem;
            }
            
            .header {
              text-align: center;
              margin-bottom: 3rem;
              padding-bottom: 2rem;
              border-bottom: 2px solid var(--border-subtle);
            }
            
            .logo {
              width: 200px;
              height: auto;
              margin-bottom: 1rem;
            }
            
            .title {
              font-size: 2.5rem;
              font-weight: 800;
              margin-bottom: 0.5rem;
              background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
              -webkit-background-clip: text;
              -webkit-text-fill-color: transparent;
              background-clip: text;
            }
            
            .subtitle {
              font-size: 1.2rem;
              color: var(--text-secondary);
              margin-bottom: 1rem;
            }
            
            .test-info {
              background: var(--bg-secondary);
              padding: 1rem;
              border-radius: 1rem;
              margin-top: 1.5rem;
            }
            
            .card {
              background: var(--bg-card);
              border-radius: 1rem;
              border: 1px solid var(--border-subtle);
              box-shadow: var(--shadow-md);
              margin-bottom: 2rem;
              overflow: hidden;
            }
            
            .card-header {
              display: flex;
              align-items: center;
              gap: 1rem;
              padding: 1.5rem;
              background: var(--bg-secondary);
              border-bottom: 1px solid var(--border-subtle);
            }
            
            .card-icon {
              font-size: 2rem;
            }
            
            .card-content {
              padding: 1.5rem;
            }
            
            .metrics-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 1rem;
              margin: 1.5rem 0;
            }
            
            .metric-card {
              background: var(--bg-secondary);
              padding: 1.5rem;
              border-radius: 0.75rem;
              text-align: center;
              border: 1px solid var(--border-light);
            }
            
            .metric-value {
              font-size: 2rem;
              font-weight: 800;
              color: var(--accent-primary);
              margin-bottom: 0.5rem;
            }
            
            .metric-label {
              color: var(--text-secondary);
              font-weight: 600;
            }
            
            .detail-row {
              display: flex;
              justify-content: space-between;
              padding: 0.75rem 0;
              border-bottom: 1px solid var(--border-light);
            }
            
            .detail-row:last-child {
              border-bottom: none;
            }
            
            .label {
              color: var(--text-secondary);
              font-weight: 500;
            }
            
            .value {
              color: var(--text-primary);
              font-weight: 600;
            }
            
            .footer {
              text-align: center;
              padding: 2rem 0;
              border-top: 1px solid var(--border-subtle);
              color: var(--text-muted);
              margin-top: 3rem;
            }
            
            .footer a {
              color: var(--accent-primary);
              text-decoration: none;
            }
            
            .footer a:hover {
              text-decoration: underline;
            }
          </style>
        </head>
        <body>
          <div class=\"container\">
            <!-- Header -->
            <header class=\"header\">
              \(logoDataURL != nil ? "<img src=\"\(logoDataURL!)\" alt=\"Battry\" class=\"logo\">" : "")
              <h1 class=\"title\">\(lang == "ru" ? "Калибровка батареи" : "Battery Calibration")</h1>
              <p class=\"subtitle\">\(lang == "ru" ? "Полный тест автономности работы" : "Complete Battery Runtime Test")</p>
              
              <div class=\"test-info\">
                <strong>\(deviceModel)</strong> • macOS \(macOSVersion)<br>
                \(lang == "ru" ? "Период тестирования:" : "Test Period:") \(startDateStr) → \(endDateStr)<br>
                \(lang == "ru" ? "Длительность:" : "Duration:") \(durationStr) \(lang == "ru" ? "ч" : "h")
              </div>
            </header>
            
            <!-- Calibration Results -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">🔋</div>
                <h2>\(lang == "ru" ? "Результаты тестирования" : "Calibration Test Results")</h2>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(avgDischargeStr)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "%/ч разряд" : "%/h discharge")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(runtimeStr)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "ч автономность" : "h runtime")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(calibration.startPercent) → \(calibration.endPercent)%</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "SOC диапазон" : "SOC Range")</div>
                  </div>
                </div>
                
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Начало теста:" : "Test Started:")</span>
                  <span class=\"value\">\(startDateStr)</span>
                </div>
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Завершение теста:" : "Test Completed:")</span>
                  <span class=\"value\">\(endDateStr)</span>
                </div>
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Общая длительность:" : "Total Duration:")</span>
                  <span class=\"value\">\(durationStr) \(lang == "ru" ? "ч" : "h")</span>
                </div>
              </div>
            </div>
            
            <!-- Battery Health Summary -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">💚</div>
                <h3>\(lang == "ru" ? "Состояние батареи" : "Battery Health")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.0f", result.healthScore))</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Общий скор" : "Health Score")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(wearText)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Износ" : "Wear")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(snapshot.cycleCount)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Циклы" : "Cycles")</div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Discharge Analysis -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">📊</div>
                <h3>\(lang == "ru" ? "Анализ разряда" : "Discharge Analysis")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Средняя скорость разряда:" : "Average Discharge Rate:")</span>
                  <span class=\"value\">\(avgDisText) %/h</span>
                </div>
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Тренд скорости разряда:" : "Discharge Rate Trend:")</span>
                  <span class=\"value\">\(trendDisText) %/h</span>
                </div>
                <div class=\"detail-row\">
                  <span class=\"label\">\(lang == "ru" ? "Оценочная автономность 100→0%:" : "Estimated Runtime 100→0%:")</span>
                  <span class=\"value\">\(runtimeText) h</span>
                </div>
              </div>
            </div>
            
            \(loadGeneratorHTML)
            
            <!-- Charts Section -->
            <section class=\"charts-section\">
              <h2 style=\"text-align: center; margin-bottom: 2rem; color: var(--text-primary);\">\(lang == "ru" ? "Графики разряда" : "Discharge Charts")</h2>
              \(generateChargeChart(history: recent, lang: lang))
              \(generateDischargeRateChart(history: recent, lang: lang))
            </section>
            
            <!-- Footer -->
            <footer class=\"footer\">
              <p>\(lang == "ru" ? "Сгенерировано приложением" : "Generated by") <a href=\"https://github.com/region23/Battry\" target=\"_blank\">Battry</a> • \(lang == "ru" ? "Мониторинг состояния батареи macOS" : "macOS Battery Health Monitoring")</p>
            </footer>
          </div>
        </body>
        </html>
        """
        
        return html
    }
    
    /// Создаёт специализированный HTML‑отчёт для быстрого теста здоровья
    static func generateQuickHealthReport(
        result: QuickHealthTest.QuickHealthResult,
        batterySnapshot: BatterySnapshot
    ) -> String? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let lang = getReportLanguage()
        
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
        let reportLanguage = AppLanguage(rawValue: lang) ?? .en
        let batteryConditionLabel = result.batteryCondition.label(language: reportLanguage)
        let measurementConfidenceLabel = result.measurementConfidence.label(language: reportLanguage)
        let sohCapacityText = result.sohCapacity.map { String(format: "%.1f%%", $0) } ?? "N/A"
        
        let html = """
        <!doctype html>
        <html lang=\"\(lang)\">
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, user-scalable=yes\">
          <title>Battry • \(lang == "ru" ? "Быстрый тест здоровья батареи" : "Quick Battery Health Test")</title>
          <meta name=\"description\" content=\"\(lang == "ru" ? "Результаты быстрого теста здоровья батареи MacBook" : "MacBook quick battery health test results")\">
          <style>
            /* CSS Custom Properties with Dark/Light Theme */
            :root {
              /* Light theme colors */
              --bg-primary: #ffffff;
              --bg-secondary: #f8fafc;
              --bg-card: #ffffff;
              --text-primary: #1e293b;
              --text-secondary: #475569;
              --text-muted: #64748b;
              --border-subtle: #e2e8f0;
              --border-light: #f1f5f9;
              --accent-primary: #0ea5e9;
              --accent-secondary: #8b5cf6;
              --success: #10b981;
              --warning: #f59e0b;
              --danger: #ef4444;
              --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
              --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
              --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
            }
            
            @media (prefers-color-scheme: dark) {
              :root {
                --bg-primary: #0f172a;
                --bg-secondary: #1e293b;
                --bg-card: #1e293b;
                --text-primary: #f1f5f9;
                --text-secondary: #cbd5e1;
                --text-muted: #94a3b8;
                --border-subtle: #334155;
                --border-light: #475569;
                --accent-primary: #38bdf8;
                --accent-secondary: #a78bfa;
                --success: #34d399;
                --warning: #fbbf24;
                --danger: #f87171;
              }
            }
            
            * {
              margin: 0;
              padding: 0;
              box-sizing: border-box;
            }
            
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              background: var(--bg-primary);
              color: var(--text-primary);
              line-height: 1.6;
              font-size: 14px;
            }
            
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 2rem;
            }
            
            .header {
              text-align: center;
              margin-bottom: 3rem;
              padding-bottom: 2rem;
              border-bottom: 2px solid var(--border-subtle);
            }
            
            .logo {
              width: 200px;
              height: auto;
              margin-bottom: 1rem;
            }
            
            .title {
              font-size: 2.5rem;
              font-weight: 800;
              margin-bottom: 0.5rem;
              background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
              -webkit-background-clip: text;
              -webkit-text-fill-color: transparent;
              background-clip: text;
            }
            
            .subtitle {
              font-size: 1.2rem;
              color: var(--text-secondary);
              margin-bottom: 1rem;
            }
            
            .test-info {
              background: var(--bg-secondary);
              padding: 1rem;
              border-radius: 1rem;
              margin-top: 1.5rem;
            }
            
            .card {
              background: var(--bg-card);
              border-radius: 1rem;
              border: 1px solid var(--border-subtle);
              box-shadow: var(--shadow-md);
              margin-bottom: 2rem;
              overflow: hidden;
            }
            
            .card-header {
              display: flex;
              align-items: center;
              gap: 1rem;
              padding: 1.5rem;
              background: var(--bg-secondary);
              border-bottom: 1px solid var(--border-subtle);
            }
            
            .card-icon {
              font-size: 2rem;
            }
            
            .card-content {
              padding: 1.5rem;
            }
            
            .health-score {
              display: flex;
              align-items: center;
              gap: 1rem;
              margin-bottom: 2rem;
            }
            
            .score-circle {
              width: 120px;
              height: 120px;
              border-radius: 50%;
              display: flex;
              align-items: center;
              justify-content: center;
              flex-direction: column;
              font-size: 2rem;
              font-weight: 800;
              color: white;
            }
            
            .score-circle.excellent { background: var(--success); }
            .score-circle.good { background: var(--warning); }
            .score-circle.fair { background: #f97316; }
            .score-circle.poor { background: var(--danger); }
            
            .score-details h3 {
              font-size: 1.5rem;
              margin-bottom: 0.5rem;
            }
            
            .metrics-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 1rem;
              margin: 1.5rem 0;
            }
            
            .metric-card {
              background: var(--bg-secondary);
              padding: 1.5rem;
              border-radius: 0.75rem;
              text-align: center;
              border: 1px solid var(--border-light);
            }
            
            .metric-value {
              font-size: 2rem;
              font-weight: 800;
              color: var(--accent-primary);
              margin-bottom: 0.5rem;
            }
            
            .metric-label {
              color: var(--text-secondary);
              font-weight: 600;
            }
            
            .metric-sublabel {
              color: var(--text-muted);
              font-size: 0.9rem;
              margin-top: 0.25rem;
            }
            
            .detail-row {
              display: flex;
              justify-content: space-between;
              padding: 0.75rem 0;
              border-bottom: 1px solid var(--border-light);
            }
            
            .detail-row:last-child {
              border-bottom: none;
            }
            
            .label {
              color: var(--text-secondary);
              font-weight: 500;
            }
            
            .value {
              color: var(--text-primary);
              font-weight: 600;
            }
            
            .recommendation {
              background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
              color: white;
              padding: 1.5rem;
              border-radius: 1rem;
              margin-top: 2rem;
              text-align: center;
            }
            
            .dcir-chart {
              margin: 1.5rem 0;
            }
            
            .stability-section {
              margin-top: 1.5rem;
            }
            
            .stability-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
              gap: 1rem;
              margin-top: 1rem;
            }
            
            .footer {
              text-align: center;
              padding: 2rem 0;
              border-top: 1px solid var(--border-subtle);
              color: var(--text-muted);
              margin-top: 3rem;
            }
            
            .footer a {
              color: var(--accent-primary);
              text-decoration: none;
            }
            
            .footer a:hover {
              text-decoration: underline;
            }
          </style>
        </head>
        <body>
          <div class=\"container\">
            <!-- Header -->
            <header class=\"header\">
              \(logoDataURL != nil ? "<img src=\"\(logoDataURL!)\" alt=\"Battry\" class=\"logo\">" : "")
              <h1 class=\"title\">\(lang == "ru" ? "Быстрый тест здоровья" : "Quick Health Test")</h1>
              <p class=\"subtitle\">\(lang == "ru" ? "Профессиональная диагностика состояния батареи" : "Professional Battery Health Diagnostics")</p>
              
              <div class=\"test-info\">
                <strong>\(deviceModel)</strong> • macOS \(macOSVersion)<br>
                \(lang == "ru" ? "Дата теста:" : "Test Date:") \(df.string(from: result.startedAt))<br>
                \(lang == "ru" ? "Длительность:" : "Duration:") \(String(format: "%.1f", result.durationMinutes)) \(lang == "ru" ? "мин" : "min")
              </div>
            </header>
            
            <!-- Health Score Overview -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">💚</div>
                <h2>\(lang == "ru" ? "Общая оценка здоровья" : "Overall Health Score")</h2>
              </div>
              <div class=\"card-content\">
                <div class=\"health-score\">
                  <div class=\"score-circle \(healthStatus.color == "success" ? "excellent" : (healthStatus.color == "warning" ? "good" : (healthStatus.color == "orange" ? "fair" : "poor")))\">
                    <div>\(String(format: "%.0f", result.healthScore))</div>
                    <div style=\"font-size: 0.8rem;\">/ 100</div>
                  </div>
                  <div class=\"score-details\">
                    <h3>\(healthStatus.label)</h3>
                    <p style=\"color: var(--text-secondary); margin-bottom: 1rem;\">\(result.recommendation)</p>
                    <div class=\"detail-row\">
                      <span class=\"label\">\(lang == "ru" ? "Состояние батареи:" : "Battery Condition:")</span>
                      <span class=\"value\">\(batteryConditionLabel)</span>
                    </div>
                    <div class=\"detail-row\">
                      <span class=\"label\">\(lang == "ru" ? "Достоверность измерения:" : "Measurement Confidence:")</span>
                      <span class=\"value\">\(measurementConfidenceLabel)</span>
                    </div>
                    <div class=\"detail-row\">
                      <span class=\"label\">\(lang == "ru" ? "Тестовый пресет:" : "Test Preset:")</span>
                      <span class=\"value\">\(result.powerPreset) (\(String(format: "%.1f", result.targetPower))W)</span>
                    </div>
                    <div class=\"detail-row\">
                      <span class=\"label\">\(lang == "ru" ? "Качество CP-контроля:" : "CP Control Quality:")</span>
                      <span class=\"value\">\(String(format: "%.0f", result.powerControlQuality))%</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Energy Analysis -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">⚡</div>
                <h3>\(lang == "ru" ? "Энергетический анализ" : "Energy Analysis")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.1f", result.sohEnergy))%</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "SOH по энергии" : "SOH Energy")</div>
                    <div class=\"metric-sublabel\">\(lang == "ru" ? "Реальная энергоотдача" : "Actual energy delivery")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.1f", result.energyDelivered80to50Wh))</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Энергия \(result.energyWindowDisplayLabel)" : "Energy \(result.energyWindowDisplayLabel)")</div>
                    <div class=\"metric-sublabel\">\(result.energyEstimateIsProvisional ? (lang == "ru" ? "Wh • предварительно" : "Wh • provisional") : "Wh")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.1f", result.averagePower))</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Средняя мощность" : "Average Power")</div>
                    <div class=\"metric-sublabel\">W</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(sohCapacityText)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "SOH по емкости" : "SOH Capacity")</div>
                    <div class=\"metric-sublabel\">\(lang == "ru" ? "maxCapacity / designCapacity" : "maxCapacity / designCapacity")</div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- DCIR Analysis -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">🔬</div>
                <h3>\(lang == "ru" ? "Анализ внутреннего сопротивления (DCIR)" : "Internal Resistance Analysis (DCIR)")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.dcirAt50Percent.map { String(format: "%.1f", $0) } ?? "N/A")</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "DCIR @50% SOC" : "DCIR @50% SOC")</div>
                    <div class=\"metric-sublabel\">\(lang == "ru" ? "мОм" : "mΩ")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.dcirAt20Percent.map { String(format: "%.1f", $0) } ?? "N/A")</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "DCIR @20% SOC" : "DCIR @20% SOC")</div>
                    <div class=\"metric-sublabel\">\(lang == "ru" ? "мОм" : "mΩ")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.kneeSOC.map { String(format: "%.0f", $0) } ?? "N/A")%</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Колено OCV" : "OCV Knee")</div>
                    <div class=\"metric-sublabel\">\(lang == "ru" ? "Индекс: " : "Index: ")\(String(format: "%.0f", result.kneeIndex))</div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Stability Analysis -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">📊</div>
                <h3>\(lang == "ru" ? "Анализ стабильности" : "Stability Analysis")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.microDropCount)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Микро-дропы (всего)" : "Micro-drops (total)")</div>
                    <div class=\"metric-sublabel\">\(String(format: "%.2f", result.microDropRatePerHour)) /h</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.microDropCountAbove20)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "≥20% SOC" : "≥20% SOC")</div>
                    <div class=\"metric-sublabel\">\(String(format: "%.2f", result.microDropRateAbove20PerHour)) /h</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(result.microDropCountBelow20)</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "<20% SOC" : "<20% SOC")</div>
                    <div class=\"metric-sublabel\">\(String(format: "%.2f", result.microDropRateBelow20PerHour)) /h</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.0f", result.stabilityScore))%</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Общая стабильность" : "Overall Stability")</div>
                    <div class=\"metric-sublabel\">\(result.unstableUnderLoad ? (lang == "ru" ? "Нестабилен под нагрузкой" : "Unstable under load") : (lang == "ru" ? "Стабилен" : "Stable"))</div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Temperature Analysis -->
            <div class=\"card\">
              <div class=\"card-header\">
                <div class=\"card-icon\">🌡️</div>
                <h3>\(lang == "ru" ? "Температурный анализ" : "Temperature Analysis")</h3>
              </div>
              <div class=\"card-content\">
                <div class=\"metrics-grid\">
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.1f", result.averageTemperature))°C</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Средняя температура" : "Average Temperature")</div>
                  </div>
                  <div class=\"metric-card\">
                    <div class=\"metric-value\">\(String(format: "%.0f", result.temperatureQuality))%</div>
                    <div class=\"metric-label\">\(lang == "ru" ? "Качество условий" : "Conditions Quality")</div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Recommendation -->
            <div class=\"recommendation\">
              <h3 style=\"margin-bottom: 1rem;\">\(lang == "ru" ? "Рекомендация" : "Recommendation")</h3>
              <p style=\"font-size: 1.1rem;\">\(result.recommendation)</p>
            </div>
            
            <!-- Footer -->
            <footer class=\"footer\">
              <p>\(lang == "ru" ? "Сгенерировано приложением" : "Generated by") <a href=\"https://github.com/region23/Battry\" target=\"_blank\">Battry</a> • \(lang == "ru" ? "Мониторинг состояния батареи macOS" : "macOS Battery Health Monitoring")</p>
            </footer>
          </div>
        </body>
        </html>
        """
        
        return html
    }

}
