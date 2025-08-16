import Foundation
import AppKit
import Combine

/// Структура метаданных отчета
struct ReportMetadata: Codable, Identifiable {
    let id: UUID
    let filename: String
    let createdAt: Date
    let healthScore: Int
    let dataPoints: Int
    let version: String
    
    init(filename: String, createdAt: Date, healthScore: Int, dataPoints: Int, version: String) {
        self.id = UUID()
        self.filename = filename
        self.createdAt = createdAt
        self.healthScore = healthScore
        self.dataPoints = dataPoints
        self.version = version
    }
    
    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: createdAt)) • \(healthScore)/100"
    }
}

/// Управление историей отчетов
class ReportHistory: ObservableObject {
    static let shared = ReportHistory()
    
    @Published var reports: [ReportMetadata] = []
    
    private let maxReports = 5
    private let reportsDirectoryName = "reports"
    private let metadataFileName = "reports.json"
    
    /// Путь к директории отчетов
    private var reportsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let battryDir = appSupport.appendingPathComponent("Battry")
        return battryDir.appendingPathComponent(reportsDirectoryName)
    }
    
    /// Путь к файлу метаданных
    private var metadataFile: URL {
        reportsDirectory.appendingPathComponent(metadataFileName)
    }
    
    init() {
        createDirectoryIfNeeded()
        loadReports()
    }
    
    /// Создает директорию для отчетов если не существует
    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create reports directory: \(error)")
        }
    }
    
    /// Загружает список отчетов из метаданных
    private func loadReports() {
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            reports = []
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedReports = try decoder.decode([ReportMetadata].self, from: data)
            
            // Фильтруем только существующие файлы
            reports = loadedReports.filter { metadata in
                let filePath = reportsDirectory.appendingPathComponent(metadata.filename)
                return FileManager.default.fileExists(atPath: filePath.path)
            }
            
            // Сортируем по дате создания (новые сверху)
            reports.sort { $0.createdAt > $1.createdAt }
            
            // Если отфильтровали некоторые файлы, сохраняем обновленный список
            if reports.count != loadedReports.count {
                saveReports()
            }
        } catch {
            print("Failed to load reports metadata: \(error)")
            reports = []
        }
    }
    
    /// Сохраняет метаданные отчетов
    private func saveReports() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(reports)
            try data.write(to: metadataFile)
        } catch {
            print("Failed to save reports metadata: \(error)")
        }
    }
    
    /// Добавляет новый отчет в историю
    func addReport(htmlContent: String, healthScore: Int, dataPoints: Int) -> URL? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "Battry_Report_\(timestamp).html"
        let filePath = reportsDirectory.appendingPathComponent(filename)
        
        do {
            try htmlContent.write(to: filePath, atomically: true, encoding: .utf8)
            
            let metadata = ReportMetadata(
                filename: filename,
                createdAt: Date(),
                healthScore: healthScore,
                dataPoints: dataPoints,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
            
            // Добавляем в начало списка
            reports.insert(metadata, at: 0)
            
            // Удаляем старые отчеты если превышен лимит
            cleanupOldReports()
            
            // Сохраняем метаданные
            saveReports()
            
            return filePath
        } catch {
            print("Failed to save report: \(error)")
            return nil
        }
    }
    
    /// Удаляет старые отчеты, оставляя только maxReports последних
    private func cleanupOldReports() {
        while reports.count > maxReports {
            let oldReport = reports.removeLast()
            let filePath = reportsDirectory.appendingPathComponent(oldReport.filename)
            
            do {
                try FileManager.default.removeItem(at: filePath)
            } catch {
                print("Failed to remove old report file: \(error)")
            }
        }
    }
    
    /// Удаляет конкретный отчет
    func deleteReport(_ metadata: ReportMetadata) {
        let filePath = reportsDirectory.appendingPathComponent(metadata.filename)
        
        do {
            try FileManager.default.removeItem(at: filePath)
            reports.removeAll { $0.id == metadata.id }
            saveReports()
        } catch {
            print("Failed to delete report: \(error)")
        }
    }
    
    /// Открывает отчет в браузере
    func openReport(_ metadata: ReportMetadata) {
        let filePath = reportsDirectory.appendingPathComponent(metadata.filename)
        
        if FileManager.default.fileExists(atPath: filePath.path) {
            NSWorkspace.shared.open(filePath)
        } else {
            // Файл не найден, удаляем из метаданных
            reports.removeAll { $0.id == metadata.id }
            saveReports()
        }
    }
    
    /// Получает полный путь к файлу отчета
    func getReportPath(_ metadata: ReportMetadata) -> URL {
        return reportsDirectory.appendingPathComponent(metadata.filename)
    }
    
    /// Очищает всю историю отчетов
    func clearAllReports() {
        for metadata in reports {
            let filePath = reportsDirectory.appendingPathComponent(metadata.filename)
            try? FileManager.default.removeItem(at: filePath)
        }
        
        reports.removeAll()
        saveReports()
    }
}
