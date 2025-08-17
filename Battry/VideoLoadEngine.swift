import Foundation
import AVFoundation
import Combine

/// Движок для видео-нагрузки с использованием AVPlayer
@MainActor
final class VideoLoadEngine: ObservableObject {
    /// Текущее состояние видео-плеера
    @Published private(set) var isRunning: Bool = false
    /// Последняя ошибка воспроизведения
    @Published private(set) var lastError: VideoLoadError? = nil
    
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerItem: AVPlayerItem?
    private var virtualTimer: Timer?
    
    /// Имя видео файла в bundle
    private let videoFileName = "sample_1080p_h264"
    private let videoFileExtension = "mp4"
    
    /// Запускает воспроизведение видео в цикле
    func start() {
        guard !isRunning else { return }
        
        do {
            try setupPlayer()
            player?.play()
            isRunning = true
            lastError = nil
            print("VideoLoadEngine: Started video playback")
        } catch let error as VideoLoadError {
            // Fallback to virtual video load if file not found
            if case .videoFileNotFound = error {
                startVirtualVideoLoad()
                lastError = nil
                print("VideoLoadEngine: Fallback to virtual video load")
            } else {
                lastError = error
                print("VideoLoadEngine: Failed to start - \(error.localizedDescription)")
            }
        } catch {
            lastError = .unknownError(error.localizedDescription)
            print("VideoLoadEngine: Failed to start - \(error)")
        }
    }
    
    /// Останавливает воспроизведение видео
    func stop() {
        guard isRunning else { return }
        
        player?.pause()
        cleanupPlayer()
        stopVirtualTimer()
        isRunning = false
        
        print("VideoLoadEngine: Stopped video playback")
    }
    
    /// Настраивает AVPlayer для циклического воспроизведения
    private func setupPlayer() throws {
        // Очищаем предыдущие ресурсы
        cleanupPlayer()
        
        // Ищем видео файл в bundle
        guard let videoURL = Bundle.main.url(forResource: videoFileName, withExtension: videoFileExtension) else {
            throw VideoLoadError.videoFileNotFound
        }
        
        // Создаём player item
        playerItem = AVPlayerItem(url: videoURL)
        guard let playerItem = playerItem else {
            throw VideoLoadError.failedToCreatePlayerItem
        }
        
        // Создаём queue player
        player = AVQueuePlayer(playerItem: playerItem)
        guard let player = player else {
            throw VideoLoadError.failedToCreatePlayer
        }
        
        // Настраиваем циклическое воспроизведение
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        
        // Настройки для эффективной GPU нагрузки
        if player.currentItem?.tracks.first != nil {
            // Принудительно активируем hardware decoding
            player.currentItem?.preferredForwardBufferDuration = 1.0
        }
        
        // Отключаем звук
        player.isMuted = true
        
        // Устанавливаем скорость воспроизведения (можно ускорить для большей нагрузки)
        player.rate = 1.0
    }
    
    /// Очищает ресурсы плеера
    private func cleanupPlayer() {
        playerLooper?.disableLooping()
        playerLooper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerItem = nil
    }
    
    deinit {
        // Can't access MainActor isolated properties in deinit
        // Player and timer cleanup will happen automatically
        player?.pause()
        virtualTimer?.invalidate()
    }
}

/// Ошибки видео-движка
enum VideoLoadError: LocalizedError {
    case videoFileNotFound
    case failedToCreatePlayerItem
    case failedToCreatePlayer
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .videoFileNotFound:
            return "Video file not found in bundle"
        case .failedToCreatePlayerItem:
            return "Failed to create player item"
        case .failedToCreatePlayer:
            return "Failed to create video player"
        case .unknownError(let description):
            return "Unknown error: \(description)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .videoFileNotFound:
            return "Video load will fallback to virtual CPU simulation"
        case .failedToCreatePlayerItem, .failedToCreatePlayer:
            return "Try restarting the application"
        case .unknownError:
            return "Contact support if the issue persists"
        }
    }
}

/// Альтернативная реализация для систем без видео файла
extension VideoLoadEngine {
    /// Запускает "виртуальную" видео нагрузку через Core Graphics
    func startVirtualVideoLoad() {
        guard !isRunning else { return }
        
        // Создаём имитацию видео декодирования через периодическое создание CGContext
        virtualTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performVirtualVideoWork()
            }
        }
        
        // Сохраняем ссылку на таймер для остановки
        if let timer = virtualTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        isRunning = true
        print("VideoLoadEngine: Started virtual video load")
    }
    
    /// Останавливает виртуальный таймер
    private func stopVirtualTimer() {
        virtualTimer?.invalidate()
        virtualTimer = nil
    }
    
    /// Выполняет работу имитирующую видео декодирование
    private func performVirtualVideoWork() {
        // Создаём CGContext для имитации GPU/графической нагрузки
        let width = 1920
        let height = 1080
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        if let ctx = context {
            // Рисуем простую анимацию для нагрузки
            ctx.setFillColor(CGColor(red: Double.random(in: 0...1), 
                                   green: Double.random(in: 0...1), 
                                   blue: Double.random(in: 0...1), 
                                   alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Создаём изображение для завершения обработки
            _ = ctx.makeImage()
        }
    }
}