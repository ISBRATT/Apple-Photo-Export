import XCTest
@testable import ExportCore

final class ExportStoreTests: XCTestCase {
    var root: URL!
    var store: ExportStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ExportStore(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testResumeDetectsCorruptAndMissingFiles() throws {
        let directory = try store.directory(for: "asset/identifier")
        let file = store.unusedURL(name: "IMG_001.HEIC", in: directory)
        try Data("original".utf8).write(to: file)
        var record = ExportRecord(creationDate: Date(timeIntervalSince1970: 100))
        try store.recordFile(file, key: "original", record: &record, directory: directory)
        let loaded = try store.read(in: directory, creationDate: nil)
        let entry = try XCTUnwrap(loaded.files["original"])
        XCTAssertTrue(try store.verified(entry, in: directory))
        XCTAssertEqual(loaded.creationDate, record.creationDate)
        try Data("corrupt".utf8).write(to: file)
        XCTAssertFalse(try store.verified(entry, in: directory))
        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(try store.verified(entry, in: directory))
    }

    func testDuplicateNamesPreserveExistingFiles() throws {
        let directory = try store.directory(for: "asset")
        let first = store.unusedURL(name: "photo.jpg", in: directory)
        try Data("keep me".utf8).write(to: first)
        let second = store.unusedURL(name: "photo.jpg", in: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "keep me")
        XCTAssertNotEqual(store.unusedURL(name: "export.json", in: directory).lastPathComponent, "export.json")
    }

    func testUntrustedNamesCannotEscapeDirectory() throws {
        let directory = try store.directory(for: "../../outside")
        XCTAssertEqual(directory.deletingLastPathComponent().path, root.path)
        for name in ["../../photo.jpg", "..", "/tmp/photo.jpg", "a\\b.jpg", ""] {
            let file = store.unusedURL(name: name, in: directory)
            XCTAssertEqual(file.deletingLastPathComponent().path, directory.path)
        }
    }

    func testAssetDirectorySymlinkIsRejected() throws {
        let link = root.appendingPathComponent(ExportStore.identifier("asset"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try store.directory(for: "asset"))
    }
}
