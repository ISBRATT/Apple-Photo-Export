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
        let directory = try store.directory(components: ["Albums", "Family", "Holiday"])
        let file = store.unusedURL(name: "IMG_001.HEIC", in: directory)
        try Data("original".utf8).write(to: file)
        var record = ExportRecord()
        let date = Date(timeIntervalSince1970: 100)
        try store.recordFile(file, key: "original", creationDate: date, record: &record, directory: directory)
        let loaded = try store.read(in: directory)
        let entry = try XCTUnwrap(loaded.files["original"])
        XCTAssertTrue(try store.verified(entry, in: directory))
        XCTAssertEqual(entry.creationDate, date)
        try Data("corrupt".utf8).write(to: file)
        XCTAssertFalse(try store.verified(entry, in: directory))
        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(try store.verified(entry, in: directory))
    }

    func testDuplicateNamesPreserveExistingFiles() throws {
        let directory = try store.directory(components: ["Albums", "Holiday"])
        let first = store.unusedURL(name: "photo.jpg", in: directory)
        try Data("keep me".utf8).write(to: first)
        let second = store.unusedURL(name: "photo.jpg", in: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "keep me")
        XCTAssertNotEqual(store.unusedURL(name: ".photo-export.json", in: directory).lastPathComponent, ".photo-export.json")
    }

    func testUntrustedNamesCannotEscapeDirectory() throws {
        XCTAssertThrowsError(try store.directory(components: ["../../outside"]))
        XCTAssertThrowsError(try store.directory(components: ["Albums", "..", "outside"]))
        let directory = try store.directory(components: ["Unfiled Photos"])
        for name in ["../../photo.jpg", "..", "/tmp/photo.jpg", "a\\b.jpg", ""] {
            let file = store.unusedURL(name: name, in: directory)
            XCTAssertEqual(file.deletingLastPathComponent().path, directory.path)
        }
    }

    func testFolderSymlinkIsRejected() throws {
        let link = root.appendingPathComponent("Albums")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try store.directory(components: ["Albums", "Holiday"]))
    }

    func testNestedAlbumStoresPhotosDirectlyAndResumesMultipleAssets() throws {
        let directory = try store.directory(components: ["Albums", "Family", "Holiday"])
        XCTAssertEqual(directory.path, root.appendingPathComponent("Albums/Family/Holiday").path)
        var record = ExportRecord()
        for id in ["asset-one", "asset-two"] {
            let file = store.unusedURL(name: "IMG_1234.jpg", in: directory)
            try Data(id.utf8).write(to: file)
            try store.recordFile(file, key: id, record: &record, directory: directory)
        }
        let loaded = try store.read(in: directory)
        XCTAssertEqual(loaded.files.count, 2)
        XCTAssertEqual(Set(loaded.files.values.map(\.filename)).count, 2)
        for entry in loaded.files.values { XCTAssertTrue(try store.verified(entry, in: directory)) }
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        XCTAssertEqual(children.count, 3) // Two photos and one hidden album manifest.
        for child in children { XCTAssertFalse(try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true) }
    }

    func testFolderNameCollisionsAreDeterministicAndReadable() throws {
        let names = [CollectionName(id: "1", title: "Holiday"), CollectionName(id: "2", title: "holiday"),
                     CollectionName(id: "3", title: "A/B"), CollectionName(id: "4", title: "A:B")]
        let resolved = FolderNames.resolve(names)
        XCTAssertEqual(resolved, FolderNames.resolve(Array(names.reversed())))
        XCTAssertEqual(resolved["1"], "Holiday")
        XCTAssertNotEqual(resolved["1"]?.lowercased(), resolved["2"]?.lowercased())
        XCTAssertNotEqual(resolved["3"], resolved["4"])
        for value in resolved.values { XCTAssertEqual(value, ExportStore.safeName(value)) }
    }

    func testLongUnicodeAlbumNamesRemainValidComponents() {
        let title = String(repeating: "📷", count: 100)
        let resolved = FolderNames.resolve([CollectionName(id: "1", title: title), CollectionName(id: "2", title: title)])
        for name in resolved.values {
            XCTAssertLessThanOrEqual(name.utf8.count, 180)
            XCTAssertEqual(name, ExportStore.safeName(name))
        }
        XCTAssertNotEqual(resolved["1"], resolved["2"])
    }
}
