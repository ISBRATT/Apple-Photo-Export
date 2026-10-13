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

@MainActor
final class ExportModel: ObservableObject {
    @Published var authorized = false
    @Published var albums: [Album] = []
    @Published var selectedAlbum = "all"
    @Published var includeVideos = false
    @Published var includeShared = true
    @Published var destination: URL?
    @Published var running = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = "Connect your Photos library to get started."
    @Published var log: [String] = []
    private var task: Task<Void, Never>?
    private var layout = LibraryLayout()

    func connect() async {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorized = permission == .authorized || permission == .limited
        guard authorized else {
            status = "Photos access denied. Enable Apple Photo Export in System Settings → Privacy & Security → Photos."
            return
        }
        layout = LibraryLayout.discover()
        albums = layout.albums
        if !albums.contains(where: { $0.id == selectedAlbum }) { selectedAlbum = "all" }
        let sharedCount = albums.filter(\.isShared).count
        status = "Connected: \(albums.count - sharedCount) albums, \(sharedCount) Shared Albums visible. Folder organization will be preserved."
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
        // Refresh membership and hierarchy so edits made in Photos are reflected.
        layout = LibraryLayout.discover()
        albums = layout.albums
        if selectedAlbum != "all", !albums.contains(where: { $0.id == selectedAlbum }) {
            status = "This album is no longer available. Refresh and choose another album."
            return
        }
        let plan = layout.plan(selected: selectedAlbum, includeVideos: includeVideos, includeShared: includeShared)
        total = plan.items.count
        completed = 0
        log = []
        guard !plan.items.isEmpty || !plan.directories.isEmpty else { status = "No matching photos found. Check your album and iCloud Photos sync."; return }
        running = true
        status = "Downloading originals from iCloud when needed…"
        task = Task {
            await Exporter().run(plan: plan, destination: destination) { [weak self] progress in
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
                        Text("Entire library · preserve folders and albums").tag("all")
                        ForEach(model.albums.filter { !$0.isShared || model.includeShared }) { Text($0.title).tag($0.id) }
                    }.disabled(!model.authorized || model.running)
                    Toggle("Include standalone videos", isOn: $model.includeVideos).disabled(model.running)
                    Toggle("Include Shared Albums (available shared copies)", isOn: $model.includeShared)
                        .disabled(model.running)
                        .onChange(of: model.includeShared) { _, enabled in
                            if !enabled, model.albums.contains(where: { $0.id == model.selectedAlbum && $0.isShared }) { model.selectedAlbum = "all" }
                        }
                    Text("Preserves your folders and albums. A photo in multiple albums is copied into each. Shared Albums must be enabled in Photos and may contain reduced-resolution copies.")
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
            Text("Photos go directly into their album folders; photos outside albums go into “Unfiled Photos”. Existing files are preserved, and repeat exports resume missing downloads.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.running {
                    ProgressView().controlSize(.small)
                    Text("\(model.completed) of \(model.total) album items")
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
