import Foundation
import Darwin

public struct RecoveryRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayID: String
    public let original: URL
    public let options: WallpaperOptions
    public var generated: [URL]
    public init(displayID: String, original: URL, options: WallpaperOptions, generated: [URL]) {
        id = UUID(); self.displayID = displayID; self.original = original; self.options = options; self.generated = generated
    }
}

@MainActor
public final class WallpaperRecoveryService {
    private struct Journal: Codable { var version = 1; var records: [RecoveryRecord] }
    public let directory: URL
    public let generatedDirectory: URL
    public private(set) var records: [RecoveryRecord] = []
    private var file: URL { directory.appendingPathComponent("recovery.json") }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.eaveapp.Eave", isDirectory: true)
    }

    public init(directory: URL) throws {
        self.directory = directory
        generatedDirectory = directory.appendingPathComponent("Generated", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
                guard journal.version == 1 else { throw EaveError.corruptRecovery }
                records = journal.records
                // Never trust a damaged journal to turn an Eave output into an original.
                guard records.allSatisfy({ $0.original.isFileURL && !$0.generated.isEmpty && !owns($0.original) && $0.generated.allSatisfy(owns) }) else {
                    throw EaveError.corruptRecovery
                }
                for record in records { _ = try record.options.dictionary() }
            } catch { throw EaveError.corruptRecovery }
        }
    }

    public func owns(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().deletingLastPathComponent() == generatedDirectory.resolvingSymlinksInPath()
    }

    public func record(for url: URL, displayID: String) -> RecoveryRecord? {
        records.first { $0.displayID == displayID && $0.generated.contains { $0.standardizedFileURL == url.standardizedFileURL } }
    }

    public func prepare(displayID: String, original: URL, options: WallpaperOptions, output: URL) throws {
        guard !owns(original), owns(output), original.isFileURL else { throw EaveError.unknownGeneratedWallpaper }
        let output = output.standardizedFileURL
        var next = records
        if let index = next.firstIndex(where: { $0.displayID == displayID && $0.original == original && $0.options == options }) {
            if !next[index].generated.contains(output) { next[index].generated.append(output) }
        } else {
            next.append(RecoveryRecord(displayID: displayID, original: original, options: options, generated: [output]))
        }
        if next == records { return }
        let data = try JSONEncoder().encode(Journal(records: next))
        try data.write(to: file, options: .atomic)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        // Commit in-memory state only after the original metadata is durable.
        records = next
    }

    public func cleanupUnreferenced(visibleWallpapers: Set<URL>) throws {
        let protected = Set(records.flatMap(\.generated).map(\.standardizedFileURL))
            .union(visibleWallpapers.map(\.standardizedFileURL))
        let files = try FileManager.default.contentsOfDirectory(at: generatedDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        for url in files where owns(url) && !protected.contains(url.standardizedFileURL) {
            // Referenced files may still be assigned to invisible Spaces. Keep them.
            let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
            if date < Date().addingTimeInterval(-86_400) && ["png", "tmp"].contains(url.pathExtension) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}

// Serializes app/diagnostic processes without installing a helper or daemon.
public final class InstanceLock {
    private let descriptor: Int32
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw NSError(domain: "Eave", code: 1, userInfo: [NSLocalizedDescriptionKey: "Eave is already running. Quit the other instance before continuing."])
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
