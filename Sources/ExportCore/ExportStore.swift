import Foundation
import CryptoKit

public struct ExportRecord: Codable {
    public var files: [String: Entry] = [:]
    public var creationDate: Date?
    public struct Entry: Codable {
        public let filename: String
        public let digest: String
    }
    public init(creationDate: Date?) { self.creationDate = creationDate }
}

public struct ExportStore {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func safeName(_ value: String) -> String {
        let name = value.components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)).joined(separator: "_")
        return name.isEmpty || name == "." || name == ".." ? "photo" : String(name.prefix(180))
    }

    public func directory(for id: String) throws -> URL {
        let url = root.appendingPathComponent(Self.identifier(id), isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard isDirectory.boolValue && values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        return url
    }

    public func read(in directory: URL, creationDate: Date?) throws -> ExportRecord {
        let url = directory.appendingPathComponent("export.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ExportRecord(creationDate: creationDate) }
        return try JSONDecoder().decode(ExportRecord.self, from: Data(contentsOf: url))
    }

    public func save(_ record: ExportRecord, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("export.json"), options: .atomic)
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
        while FileManager.default.fileExists(atPath: url.path) || safe == "export.json" && counter == 1 {
            url = directory.appendingPathComponent("\(counter)-\(safe)")
            counter += 1
        }
        return url
    }

    public func recordFile(_ url: URL, key: String, record: inout ExportRecord, directory: URL) throws {
        record.files[key] = .init(filename: url.lastPathComponent, digest: try Self.digest(url))
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
