import Foundation

enum AppSupportPaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return base
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    static func battryDirectory(fileManager: FileManager = .default) -> URL {
        let dir = applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Battry", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

