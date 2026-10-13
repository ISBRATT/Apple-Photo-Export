import Foundation
import Photos
import ExportCore

struct ExportProgress: Sendable {
    let completed: Int
    let total: Int
    let exported: Int
    let skipped: Int
    let failed: Int
    let message: String
}

actor Exporter {
    func run(plan: ExportPlan, destination: URL, progress: @escaping @MainActor @Sendable (ExportProgress) -> Void) async {
        let root = destination.appendingPathComponent("Apple Photo Export", isDirectory: true)
        let store = ExportStore(root: root)
        var exported = 0, skipped = 0, failed = 0, completed = 0
        do {
            _ = try store.directory(components: [])
            for path in plan.directories {
                try Task.checkCancellation()
                _ = try store.directory(components: path)
            }
            for item in plan.items {
                try Task.checkCancellation()
                let asset = item.asset
                var message = ""
                do {
                    let directory = try store.directory(components: item.path)
                    var record = try store.read(in: directory)
                    // Original stills, RAW alternatives, videos and Live Photo companions.
                    let resources = PHAssetResource.assetResources(for: asset).filter {
                        [.photo, .alternatePhoto, .video, .pairedVideo, .audio].contains($0.type)
                    }
                    guard !resources.isEmpty else { throw CocoaError(.fileReadUnknown) }
                    for (index, resource) in resources.enumerated() {
                        try Task.checkCancellation()
                        let key = "\(ExportStore.identifier(asset.localIdentifier))-\(resource.type.rawValue)-\(index)-\(resource.originalFilename)"
                        if let entry = record.files[key], try store.verified(entry, in: directory) {
                            skipped += 1
                            continue
                        }
                        let temporary = directory.appendingPathComponent(".download-\(UUID().uuidString)")
                        do {
                            try await download(resource, to: temporary)
                            try Task.checkCancellation()
                            let target = store.unusedURL(name: resource.originalFilename, in: directory)
                            try FileManager.default.moveItem(at: temporary, to: target)
                            if let date = asset.creationDate {
                                try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: target.path)
                            }
                            try store.recordFile(target, key: key, creationDate: asset.creationDate, record: &record, directory: directory)
                            exported += 1
                        } catch {
                            try? FileManager.default.removeItem(at: temporary)
                            throw error
                        }
                    }
                    message = "\(item.path.joined(separator: " / ")): \(resources.first?.originalFilename ?? "photo")\(item.isShared ? " (shared copy)" : "")"
                } catch is CancellationError { throw CancellationError() }
                catch {
                    failed += 1
                    message = "Failed in \(item.path.joined(separator: " / ")): \(error.localizedDescription)\(item.isShared ? " — this shared item may not be downloadable through Photos." : "")"
                }
                completed += 1
                await progress(.init(completed: completed, total: plan.items.count, exported: exported, skipped: skipped, failed: failed, message: message))
            }
            await progress(.init(completed: completed, total: plan.items.count, exported: exported, skipped: skipped, failed: failed, message: "Finished. \(exported) files exported, \(skipped) verified files skipped, \(failed) album items failed."))
        } catch {
            let message = error is CancellationError ? "Export stopped. Completed files are saved; run again to resume." : "Export stopped: \(error.localizedDescription)"
            await progress(.init(completed: completed, total: plan.items.count, exported: exported, skipped: skipped, failed: failed, message: message))
        }
    }

    private func download(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
