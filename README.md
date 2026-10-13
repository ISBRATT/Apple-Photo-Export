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

The script runs the unit tests, builds a release executable, creates a bundle with the required Photos permission description, and signs it locally. This is a local development build, not a notarized distribution. Launch the app bundle rather than running the bare executable so macOS can identify its Photos permission request.

## Export your library

1. Sign in to your Apple Account on your Mac. In **Photos → Settings → iCloud**, enable **iCloud Photos**. Open Photos and allow library sync to complete. “Optimize Mac Storage” is supported: missing originals are downloaded during export.
2. Open Apple Photo Export and click **Connect Photos**. Grant access when macOS prompts.
3. Select all photos or an album. Optionally include standalone videos; Live Photo video companions are always included.
4. Choose a folder on your hard drive and click **Export originals**. Keep the Mac awake and the drive connected.

The app uses Apple's Photos framework and your existing Mac sign-in. It does not request or store your Apple password. It exports only assets visible in the current Mac Photos library, not a separate direct connection to all of iCloud. Shared Albums, hidden items, and library access restrictions may limit what Photos exposes.

## Export layout and recovery

```
Chosen folder/
  Apple Photo Export/
    <stable asset identifier hash>/
      IMG_1234.HEIC
      IMG_1234.MOV
      export.json
```

Each asset gets its own folder so photos with identical camera filenames do not collide. Original names and embedded metadata are retained; creation dates are also saved in the manifest and applied to output files. Unmodified originals, available RAW alternatives, and Live Photo companions are included. Edits, album organization, captions, and favorites are not exported. This is a file export, not a complete Photos library backup.

Completed resources are recorded atomically with SHA-256 checksums. Subsequent exports to the same destination verify those files and download missing or changed files again, keeping pre-existing files under their existing names. Asset identifiers belong to this Photos library; a different library may produce duplicate exports. Do not modify the generated manifests while exporting.

**Stop export** stops after the current Photos download finishes. Partial download files are cleaned up. Completed files remain. Failed assets are reported while other assets continue; repeat the export to retry. Ensure sufficient free space for the originals and a temporary copy of the current resource. Disk disconnects, unavailable originals, and network errors can cause failures.

## Development and validation

```sh
swift test
bash scripts/build-app.sh
```

Unit tests exercise checksum-based resume, file corruption, missing files, filename collisions, path handling, and symlink rejection. GitHub Actions builds and tests on macOS and uploads the app bundle as a ZIP.

The Linux cloud workspace cannot compile Apple's Photos/SwiftUI frameworks. macOS compilation, permission prompts, and live iCloud downloads must be validated on a Mac. For a manual smoke test, export an album containing an iCloud-only photo, a Live Photo, and a RAW photo if available. Confirm outputs open correctly, rerun and confirm verified files are skipped, then delete one exported original and rerun to confirm recovery. Also check permission denial, cancellation, and a disconnected destination drive. No live Apple account has been used for testing in the cloud workspace.
