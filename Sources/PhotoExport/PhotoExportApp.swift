import SwiftUI
import AppKit
import Photos

@main
struct PhotoExportApp: App {
    @StateObject private var model = ExportModel()
    var body: some Scene {
        WindowGroup("Apple Photo Export") {
            ContentView(model: model)
                .frame(minWidth: 680, minHeight: 570)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 740, height: 650)
    }
}

struct Album: Identifiable {
    let id: String
    let title: String
    let collection: PHAssetCollection
}

@MainActor
final class ExportModel: ObservableObject {
    @Published var authorized = false
    @Published var albums: [Album] = []
    @Published var selectedAlbum = "all"
    @Published var includeVideos = false
    @Published var destination: URL?
    @Published var running = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = "Connect your Photos library to get started."
    @Published var log: [String] = []
    private var task: Task<Void, Never>?

    func connect() async {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorized = permission == .authorized || permission == .limited
        guard authorized else {
            status = "Photos access denied. Enable Apple Photo Export in System Settings → Privacy & Security → Photos."
            return
        }
        albums = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            self.albums.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "Untitled album", collection: collection))
        }
        albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        status = "Photos connected. Only items currently visible in this Mac’s Photos library are available."
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export here"
        if panel.runModal() == .OK { destination = panel.url }
    }

    func start() {
        guard authorized, let destination, !running else { return }
        let options = PHFetchOptions()
        if !includeVideos { options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue) }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result: PHFetchResult<PHAsset>
        if let album = albums.first(where: { $0.id == selectedAlbum }) {
            result = PHAsset.fetchAssets(in: album.collection, options: options)
        } else { result = PHAsset.fetchAssets(with: options) }
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        total = assets.count
        completed = 0
        log = []
        guard !assets.isEmpty else { status = "No matching photos found. Check your album and iCloud Photos sync."; return }
        running = true
        status = "Downloading originals from iCloud when needed…"
        task = Task {
            await Exporter().run(assets: assets, destination: destination) { [weak self] progress in
                guard let self else { return }
                self.completed = progress.completed
                self.status = progress.message
                self.log.append(progress.message)
                if self.log.count > 200 { self.log.removeFirst() }
            }
            running = false
            task = nil
        }
    }

    func stop() {
        task?.cancel()
        status = "Stopping after the current download finishes…"
    }
}

struct ContentView: View {
    @ObservedObject var model: ExportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "photo.stack.fill").font(.system(size: 36)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Photo Export").font(.largeTitle.bold())
                    Text("Your originals. On your own drive.").foregroundStyle(.secondary)
                }
            }
            Text("Uses the Photos library on this Mac. Enable iCloud Photos in Photos → Settings → iCloud before exporting.")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(model.authorized ? "Photos library connected" : "Photos access required", systemImage: model.authorized ? "checkmark.circle.fill" : "lock.fill")
                        Spacer()
                        Button(model.authorized ? "Refresh albums" : "Connect Photos") { Task { await model.connect() } }
                            .disabled(model.running)
                    }
                    Picker("Export", selection: $model.selectedAlbum) {
                        Text("All photos").tag("all")
                        ForEach(model.albums) { Text($0.title).tag($0.id) }
                    }.disabled(!model.authorized || model.running)
                    Toggle("Include standalone videos", isOn: $model.includeVideos).disabled(model.running)
                    Text("Exports unmodified originals, RAW alternatives, and Live Photo companions. Albums are a filter; edited versions and album organization are not exported.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("Destination") {
                HStack {
                    Image(systemName: "externaldrive.fill").foregroundStyle(.blue)
                    Text(model.destination?.path ?? "Choose a folder on your hard drive").lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button("Choose folder…") { model.chooseDirectory() }.disabled(model.running)
                }.padding(8)
            }
            Text("Files go into “Apple Photo Export”, with a separate folder per photo. Existing files are preserved. Repeat exports verify saved files and resume missing downloads.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.running {
                    ProgressView().controlSize(.small)
                    Text("\(model.completed) of \(model.total) assets")
                    Spacer()
                    Button("Stop export") { model.stop() }
                } else {
                    Spacer()
                    Button("Export originals") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.authorized || model.destination == nil)
                }
            }
            if model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
            Text(model.status).font(.callout).textSelection(.enabled)
            if !model.log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 130)
            }
            Spacer(minLength: 0)
        }.padding(28)
    }
}
