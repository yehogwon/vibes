import Foundation

/// Decides where the scratchpad lives: the app's iCloud Drive folder when iCloud is available,
/// otherwise a local file.
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

    public enum ICloudStatus: Equatable, Sendable {
        /// The `Documents` folder of the app's iCloud container.
        case available(URL)
        /// Not signed in to iCloud, or iCloud Drive is off.
        case signedOut
        /// This build isn't signed with the iCloud entitlement.
        case notEntitled

        public var documentsURL: URL? {
            if case .available(let url) = self { url } else { nil }
        }
    }

    /// Whether the app can use iCloud Drive right now.
    ///
    /// This can block while the container is set up; don't call it on the main thread.
    public static func iCloudStatus() -> ICloudStatus {
        guard FileManager.default.ubiquityIdentityToken != nil else { return .signedOut }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return .notEntitled
        }
        return .available(container.appendingPathComponent("Documents", isDirectory: true))
    }

    /// Picks the scratchpad's location and, the first time iCloud is available, moves the local
    /// file into it. Nothing is deleted: if both places already have different text, the local
    /// version is kept next to the iCloud one.
    ///
    /// - Parameters:
    ///   - cloudDocuments: Where iCloud files go, from ``iCloudStatus()``.
    ///   - move: Moves a file into iCloud. Defaults to `FileManager.setUbiquitous`; tests
    ///     substitute a plain move.
    public static func resolve(
        localURL: URL,
        cloudDocuments: URL?,
        deviceName: String = "this Mac",
        move: (URL, URL) throws -> Void = {
            try FileManager.default.setUbiquitous(true, itemAt: $0, destinationURL: $1)
        }
    ) -> Resolution {
        guard let cloudDocuments else {
            return Resolution(location: .local(localURL))
        }
        let cloudURL = cloudDocuments.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: localURL.path) else {
            return Resolution(location: .iCloud(cloudURL))
        }

        do {
            try fileManager.createDirectory(at: cloudDocuments, withIntermediateDirectories: true)
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
            let kept = uniqueURL(cloudDocuments.appendingPathComponent(keptName))
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
