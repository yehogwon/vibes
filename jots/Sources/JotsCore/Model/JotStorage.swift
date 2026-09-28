import Foundation

/// Decides where the scratchpad lives: a Jots folder in iCloud Drive when iCloud Drive is on,
/// otherwise a local file.
///
/// iCloud Drive syncs whatever is in its folder, so the app writes there directly instead of
/// through an iCloud container, which would need the app to be signed with iCloud entitlements.
public enum JotStorage {
    public static let fileName = "Jots.md"

    public enum Location: Equatable, Sendable {
        case iCloud(URL)
        case local(URL)

        public var url: URL {
            switch self {
            case .iCloud(let url), .local(let url): url
            }
        }
    }

    public struct Resolution: Equatable, Sendable {
        public var location: Location
        /// Something worth telling the user, e.g. that two versions were kept.
        public var notice: String?
    }

    /// The Jots folder in iCloud Drive, or `nil` when iCloud Drive is off or no one is signed in.
    public static func iCloudFolder() -> URL? {
        guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Jots", isDirectory: true)
    }

    /// Moves the scratchpad out of the folder the sandboxed builds kept it in, the first time an
    /// unsandboxed build runs. Returns a message if the move failed, so the text isn't silently
    /// left behind.
    public static func adoptSandboxedFile(from oldURL: URL, to localURL: URL) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: oldURL.path), !fileManager.fileExists(atPath: localURL.path) else {
            return nil
        }
        do {
            try fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: oldURL, to: localURL)
            return nil
        } catch {
            return "Couldn't move your scratchpad from \(oldURL.path): \(error.localizedDescription)"
        }
    }

    /// Picks the scratchpad's location and, the first time iCloud is available, moves the local
    /// file into it. Nothing is deleted: if both places already have different text, the local
    /// version is kept next to the iCloud one.
    ///
    /// - Parameters:
    ///   - cloudFolder: Where the scratchpad goes in iCloud Drive, from ``iCloudFolder()``.
    ///   - move: Moves a file into iCloud. Tests substitute one that fails.
    public static func resolve(
        localURL: URL,
        cloudFolder: URL?,
        deviceName: String = "this Mac",
        move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) -> Resolution {
        guard let cloudFolder else {
            return Resolution(location: .local(localURL))
        }
        let cloudURL = cloudFolder.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: localURL.path) else {
            return Resolution(location: .iCloud(cloudURL))
        }

        do {
            try fileManager.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
            let cloudExists = fileManager.fileExists(atPath: cloudURL.path) || Cloud.isNotDownloaded(cloudURL)
            if !cloudExists {
                try move(localURL, cloudURL)
                return Resolution(location: .iCloud(cloudURL))
            }
            if let local = try? Data(contentsOf: localURL), let cloud = try? Data(contentsOf: cloudURL), local == cloud
            {
                try fileManager.removeItem(at: localURL)
                return Resolution(location: .iCloud(cloudURL))
            }
            let keptName = "Jots (from \(deviceName)).md"
            let kept = uniqueURL(cloudFolder.appendingPathComponent(keptName))
            try move(localURL, kept)
            return Resolution(
                location: .iCloud(cloudURL),
                notice:
                    "iCloud already had a scratchpad, so this Mac's version was kept as \"\(kept.lastPathComponent)\"."
            )
        } catch {
            // Keep working locally rather than risk the text.
            return Resolution(
                location: .local(localURL),
                notice: "Couldn't move the scratchpad to iCloud: \(error.localizedDescription)")
        }
    }

    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = url.deletingPathExtension().lastPathComponent
            candidate = url.deletingLastPathComponent().appendingPathComponent(
                "\(base) \(counter).\(url.pathExtension)")
            counter += 1
        }
        return candidate
    }
}
