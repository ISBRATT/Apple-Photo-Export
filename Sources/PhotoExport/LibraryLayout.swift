import Foundation
import Photos
import ExportCore

struct Album: Identifiable {
    let id: String
    let path: [String]
    let collection: PHAssetCollection
    let isShared: Bool
    var title: String { path.joined(separator: " / ") }
}

struct LibraryLayout {
    var albums: [Album] = []
    var folders: [[String]] = []

    static func discover() -> LibraryLayout {
        var layout = LibraryLayout()
        var visited = Set<String>()

        func walk(_ result: PHFetchResult<PHCollection>, parent: [String]) {
            var collections: [PHCollection] = []
            result.enumerateObjects { collection, _, _ in collections.append(collection) }
            let names = FolderNames.resolve(collections.map { CollectionName(id: $0.localIdentifier, title: $0.localizedTitle ?? "Untitled") })
            for collection in collections {
                guard visited.insert(collection.localIdentifier).inserted else { continue }
                let path = parent + [names[collection.localIdentifier]!]
                if let folder = collection as? PHCollectionList {
                    layout.folders.append(path)
                    walk(PHCollection.fetchCollections(in: folder, options: nil), parent: path)
                } else if let album = collection as? PHAssetCollection, album.assetCollectionSubtype != .albumCloudShared {
                    layout.albums.append(Album(id: album.localIdentifier, path: path, collection: album, isShared: false))
                }
            }
        }

        walk(PHCollection.fetchTopLevelUserCollections(with: nil), parent: ["Albums"])
        let shared = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
        var sharedCollections: [PHAssetCollection] = []
        shared.enumerateObjects { collection, _, _ in sharedCollections.append(collection) }
        let names = FolderNames.resolve(sharedCollections.map { CollectionName(id: $0.localIdentifier, title: $0.localizedTitle ?? "Untitled") })
        for collection in sharedCollections {
            layout.albums.append(Album(id: collection.localIdentifier, path: ["Shared Albums", names[collection.localIdentifier]!], collection: collection, isShared: true))
        }
        layout.albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return layout
    }

    func plan(selected: String, includeVideos: Bool, includeShared: Bool) -> ExportPlan {
        func options(shared: Bool = false) -> PHFetchOptions {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = shared ? .typeCloudShared : [.typeUserLibrary, .typeiTunesSynced]
            if !includeVideos { options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue) }
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            return options
        }
        var plan = ExportPlan()
        var filed = Set<String>()
        let chosen = albums.filter { (selected == "all" || $0.id == selected) && (!$0.isShared || includeShared) }
        if selected == "all" { plan.directories = folders }
        for album in chosen {
            plan.directories.append(album.path)
            let assets = PHAsset.fetchAssets(in: album.collection, options: options(shared: album.isShared))
            assets.enumerateObjects { asset, _, _ in
                if !album.isShared { filed.insert(asset.localIdentifier) }
                plan.items.append(ExportItem(asset: asset, path: album.path, isShared: album.isShared))
            }
        }
        if selected == "all" {
            let library = PHAsset.fetchAssets(with: options())
            library.enumerateObjects { asset, _, _ in
                if !filed.contains(asset.localIdentifier) {
                    plan.items.append(ExportItem(asset: asset, path: ["Unfiled Photos"], isShared: false))
                }
            }
        }
        return plan
    }
}

struct ExportItem {
    let asset: PHAsset
    let path: [String]
    let isShared: Bool
}

struct ExportPlan {
    var items: [ExportItem] = []
    var directories: [[String]] = []
}
