import Foundation

public enum KarabinerInstallerError: LocalizedError {
    case noDiskImage
    case badResponse(Int)
    case mountFailed(String)
    case noPackage
    case untrusted(String)

    public var errorDescription: String? {
        switch self {
        case .noDiskImage: "В последнем релизе Karabiner-Elements нет установочного образа."
        case .badResponse(let code): "GitHub ответил с кодом \(code)."
        case .mountFailed(let output): "Не удалось открыть образ: \(output)"
        case .noPackage: "В образе Karabiner-Elements не найден установщик .pkg."
        case .untrusted(let reason): "Установщик не прошёл проверку подписи: \(reason)"
        }
    }
}

public struct KarabinerRelease: Equatable, Sendable {
    public var version: String
    public var diskImage: URL
    public var size: Int
}

/// Скачивание официального Karabiner-Elements с GitHub pqrs.org и проверка подписи установщика.
///
/// Сам пакет ставит стандартный установщик macOS (с паролем администратора), CtrlAlt его только открывает.
public enum KarabinerInstaller {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/pqrs-org/Karabiner-Elements/releases/latest")!
    /// Team ID разработчика Karabiner-Elements (Fumihiko Takayama).
    public static let teamID = "G43BCU2T37"

    public static func parseLatestRelease(_ data: Data) throws -> KarabinerRelease {
        struct Release: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: URL
                var size: Int
            }
            var tag_name: String
            var assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Karabiner-Elements") && $0.name.hasSuffix(".dmg") }),
              asset.browser_download_url.host() == "github.com"
        else { throw KarabinerInstallerError.noDiskImage }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return KarabinerRelease(version: version, diskImage: asset.browser_download_url, size: asset.size)
    }

    public static func fetchLatestRelease() async throws -> KarabinerRelease {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw KarabinerInstallerError.badResponse(http.statusCode)
        }
        return try parseLatestRelease(data)
    }

    /// Папка для скачанного образа и извлечённого установщика.
    public static var workDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "CtrlAlt/Karabiner")
    }

    /// Скачивает образ; `progress` получает долю от 0 до 1.
    public static func download(_ release: KarabinerRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let directory = workDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: release.diskImage.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        return try await DownloadDelegate.run(url: release.diskImage, to: destination, progress: progress)
    }

    /// Монтирует образ, находит .pkg, проверяет подпись и копирует его рядом с образом.
    /// Возвращает путь к проверенному установщику; образ отмонтируется.
    public static func extractVerifiedPackage(from diskImage: URL) throws -> URL {
        let mountPoint = workDirectory.appending(path: "mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mountPoint) }

        let attach = try Karabiner.run("/usr/bin/hdiutil", ["attach", diskImage.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path])
        guard attach.status == 0 else { throw KarabinerInstallerError.mountFailed(attach.output) }
        defer { _ = try? Karabiner.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let items = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        guard let package = items.first(where: { $0.pathExtension == "pkg" }) else { throw KarabinerInstallerError.noPackage }
        try verifyPackage(package)

        let copy = workDirectory.appending(path: package.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: package, to: copy)
        // Копия проверяется ещё раз: открывать будем именно её.
        try verifyPackage(copy)
        return copy
    }

    /// Подпись Developer ID Installer от разработчика Karabiner и нотаризация Apple.
    public static func verifyPackage(_ package: URL) throws {
        let signature = try Karabiner.run("/usr/sbin/pkgutil", ["--check-signature", package.path])
        guard signature.status == 0, isTrustedSignature(signature.output) else {
            throw KarabinerInstallerError.untrusted(signature.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let gatekeeper = try Karabiner.run("/usr/sbin/spctl", ["--assess", "--type", "install", "-vv", package.path])
        guard gatekeeper.status == 0 else {
            throw KarabinerInstallerError.untrusted(gatekeeper.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Разбор вывода `pkgutil --check-signature`: подпись Apple и первый сертификат цепочки — наш разработчик.
    public static func isTrustedSignature(_ output: String) -> Bool {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0.hasPrefix("Status: signed by a developer certificate issued by Apple") }) else { return false }
        guard let leaf = lines.first(where: { $0.hasPrefix("1. ") }) else { return false }
        return leaf.hasPrefix("1. Developer ID Installer:") && leaf.hasSuffix("(\(teamID))")
    }
}

/// Скачивание с прогрессом через URLSessionDownloadDelegate.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var moveError: Error?

    private init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func run(url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Временный файл удаляется сразу после возврата, поэтому переносим здесь.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            moveError = KarabinerInstallerError.badResponse(http.statusCode)
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: destination)
        }
        continuation = nil
    }
}
