import Foundation
import CryptoKit

public struct ExportRecord: Codable {
    public var files: [String: Entry] = [:]
    public struct Entry: Codable {
        public let filename: String
        public let digest: String
        public let creationDate: Date?
    }
    public init() {}
}

public struct ExportStore {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func safeName(_ value: String) -> String {
        var name = value.components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)).joined(separator: "_")
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty || name == "." || name == ".." ? "photo" : name
    }

    /// Resolve every level separately so existing symlinks cannot redirect writes.
    public func directory(components: [String]) throws -> URL {
        var url = root
        try ensureDirectory(url)
        for component in components {
            guard component == Self.safeName(component) else { throw CocoaError(.fileWriteInvalidFileName) }
            url.appendPathComponent(component, isDirectory: true)
            try ensureDirectory(url)
        }
        return url
    }

    private func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard isDirectory.boolValue && values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
    }

    public func read(in directory: URL) throws -> ExportRecord {
        let url = directory.appendingPathComponent(".photo-export.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ExportRecord() }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw CocoaError(.fileReadInvalidFileName) }
        return try JSONDecoder().decode(ExportRecord.self, from: Data(contentsOf: url))
    }

    public func save(_ record: ExportRecord, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent(".photo-export.json"), options: .atomic)
    }

    public func verified(_ entry: ExportRecord.Entry, in directory: URL) throws -> Bool {
        guard entry.filename == Self.safeName(entry.filename) else { return false }
        let url = directory.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { return false }
        return try Self.digest(url) == entry.digest
    }

    public func unusedURL(name: String, in directory: URL) -> URL {
        let safe = Self.safeName(name)
        var url = directory.appendingPathComponent(safe)
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) || safe == ".photo-export.json" && counter == 1 {
            url = directory.appendingPathComponent(Self.safeName("\(counter)-\(safe)"))
            counter += 1
        }
        return url
    }

    public func recordFile(_ url: URL, key: String, creationDate: Date? = nil, record: inout ExportRecord, directory: URL) throws {
        record.files[key] = .init(filename: url.lastPathComponent, digest: try Self.digest(url), creationDate: creationDate)
        try save(record, in: directory)
    }

    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct CollectionName {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public enum FolderNames {
    /// Preserve readable titles, disambiguating sanitized or case-insensitive collisions.
    public static func resolve(_ collections: [CollectionName]) -> [String: String] {
        var result: [String: String] = [:]
        var used = Set<String>()
        for collection in collections.sorted(by: { $0.id < $1.id }) {
            let base = ExportStore.safeName(collection.title)
            var name = base
            var counter = 1
            while used.contains(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))) {
                var shortBase = base
                while shortBase.utf8.count > 140 { shortBase.removeLast() }
                name = "\(shortBase) (\(ExportStore.identifier(collection.id).prefix(10))-\(counter))"
                counter += 1
            }
            used.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))
            result[collection.id] = name
        }
        return result
    }
}
