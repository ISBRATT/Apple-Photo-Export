# Apple Photo Export

A native macOS app for exporting unmodified originals from your iCloud-synced Photos library to a folder on an internal or external hard drive.

## Build and launch

Requires **macOS 14 or later** and Xcode Command Line Tools (Swift 5.9+). There are no third-party dependencies.

```sh
xcode-select --install  # Only if Command Line Tools are not already installed
git clone https://github.com/ISBRATT/Apple-Photo-Export.git
cd Apple-Photo-Export
bash scripts/build-app.sh
open 'dist/Apple Photo Export.app'
```

The script builds a release executable, creates a bundle with the required Photos permission description, and signs it locally. Unit tests run separately and are required in CI. This is a local development build, not a notarized distribution. Launch the app bundle rather than running the bare executable so macOS can identify its Photos permission request.

## Export your library

1. Sign in to your Apple Account on your Mac. In **Photos → Settings → iCloud**, enable **iCloud Photos**. Open Photos and allow library sync to complete. “Optimize Mac Storage” is supported: missing originals are downloaded during export.
2. Open Apple Photo Export and click **Connect Photos**. Grant access when macOS prompts.
3. Select the entire library or an album. The entire-library export preserves your user folders and albums, including empty folders and albums. Optionally include standalone videos; Live Photo video companions are always included. Shared Albums are included by default and can be switched off.
4. Choose a folder on your hard drive and click **Export originals**. Keep the Mac awake and the drive connected.

The app uses Apple's Photos framework and your existing Mac sign-in. It does not request or store your Apple password. It exports only assets visible in the current Mac Photos library, not a separate direct connection to all of iCloud. Hidden items and library access restrictions may limit what Photos exposes. Enable Shared Albums in Photos settings if you want to export them. The connection status reports how many Shared Albums Photos exposes to this app; it cannot discover unavailable albums directly from iCloud.

## Export layout and recovery

```
Chosen folder/
  Apple Photo Export/
    Albums/
      Family/
        Summer Holiday/
          IMG_1234.HEIC
          IMG_1234.MOV
          IMG_1235.JPG
    Unfiled Photos/
      IMG_5678.HEIC
    Shared Albums/
      Family Updates/
        IMG_9012.JPG
```

Photos sit directly inside their album folders, with your nested Photos folders above them. A photo in several albums is copied into each, which uses extra disk space. Library photos outside user albums go into **Unfiled Photos**. Selecting a single album keeps its folder path and exports only that album. Photos' automatically generated Smart Albums (such as Recents or Screenshots) are not recreated as directories.

Original filenames and embedded metadata are retained when possible; duplicate filenames receive a numeric prefix. Album/folder titles are preserved with filesystem-unsafe characters replaced. Duplicate sibling titles receive a distinguishing suffix, including titles that differ only in capitalization. Creation dates are saved in hidden `.photo-export.json` manifests alongside each album's files and applied to output files. There is no separate directory for each photo.

Unmodified originals, available RAW alternatives, and Live Photo companions are included. **Shared Albums export the copies available through Photos, which may have reduced resolution; these are not guaranteed originals.** Unavailable shared resources are reported as failures while other items continue. Shared comments, likes, participants, edited versions, captions, favorites, and album photo ordering are not exported. This is a file export, not a complete Photos library backup.

Completed resources are recorded atomically with SHA-256 checksums. Subsequent exports to the same destination verify those files and download missing or changed files again, keeping pre-existing files under their existing names. Asset identifiers belong to this Photos library; a different library may produce duplicate exports. Do not modify the generated manifests while exporting. Folder/album renames create new paths on the next export; old folders and removed album memberships are retained rather than deleted.

Exports from the earlier version with one hashed directory per photo are left untouched. This version writes the new album layout without migrating or deleting those old files; exporting again may therefore use extra space.

**Stop export** stops after the current Photos download finishes. Partial download files are cleaned up. Completed files remain. Failed assets are reported while other assets continue; repeat the export to retry. Ensure sufficient free space for the originals and a temporary copy of the current resource. Disk disconnects, unavailable originals, and network errors can cause failures.

## Development and validation

```sh
swift test
bash scripts/build-app.sh
```

Unit tests exercise nested album paths, multiple photos in the same directory, deterministic album-name collisions, long Unicode titles, checksum-based resume, file corruption, missing files, filename collisions, path handling, and symlink rejection. GitHub Actions builds and tests on macOS and uploads the app bundle as a ZIP.

If `swift test` reports that `XCTest` cannot be found, use full Xcode for tests. After installing Xcode and completing its first-launch setup, run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Some Command Line Tools installations do not provide the XCTest framework. This does not prevent using the app build script, which builds only the application product.

The Linux cloud workspace cannot compile Apple's Photos/SwiftUI frameworks. macOS compilation, permission prompts, and live iCloud downloads must be validated on a Mac. For a manual smoke test, create a folder containing a nested folder and two albums, place one photo in both albums, and leave another photo outside any album. Export the entire library and verify the directory hierarchy, duplicate membership copies, and Unfiled Photos output. Also test duplicate album names, an empty album, and a visible Shared Album. Confirm exported copies open correctly, including an iCloud-only photo, a Live Photo, and a RAW photo if available. Rerun and confirm verified files are skipped, then delete one exported original and rerun to confirm recovery. Also check permission denial, cancellation, and a disconnected destination drive. No live Apple account has been used for testing in the cloud workspace.
