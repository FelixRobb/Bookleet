# Bookleet

Bookleet is a native macOS SwiftUI app for turning ordinary PDFs into print-ready booklet PDFs.

## Run in Xcode

1. Open `Bookleet.xcodeproj` in Xcode.
2. Select the **Bookleet** scheme.
3. Set your **Team** under Signing & Capabilities (target **Bookleet**).
4. Press Run.

## Command line

Build the `bookleet` tool (Xcode scheme **BookleetCLI**, or `xcodebuild -target BookleetCLI`), then run:

```bash
bookleet document.pdf
bookleet -o output.pdf --paper a4 --margin 12 manual.pdf
bookleet --page-range 3-20 --page-numbers outside report.pdf
bookleet --help
```

The CLI uses the same imposition engine as the app. Output defaults to `<input>-booklet.pdf` beside the source file.

## Project layout

```
Bookleet/           App source, Info.plist, entitlements, assets
BookleetCLI/        Command-line tool entry point
BookleetTests/      Unit tests
Bookleet.xcodeproj  Xcode project
```

The `.xcodeproj` is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing targets or build settings in `project.yml`, run `xcodegen generate`.

## Build & distribute

- **Debug run:** Product → Run (⌘R)
- **Release archive:** Product → Archive, then distribute or export from the Organizer
- **Command line:** `xcodebuild -project Bookleet.xcodeproj -scheme Bookleet -configuration Release archive`
- **Tests:** Product → Test (⌘U), or `xcodebuild test -project Bookleet.xcodeproj -scheme Bookleet -destination 'platform=macOS'`

Bundle ID: `com.bookleet.Bookleet`. Add app icon images to `Bookleet/Assets.xcassets/AppIcon.appiconset/`.

## What works now

- Import PDF documents by file picker or drag and drop.
- Import images as single-page documents.
- Generate saddle-stitch booklet page order with blank-page padding.
- Split thick documents into bound signatures (sheets per fold) instead of one impossible-to-fold stack.
- Apply creep (push-out) compensation so fore-edge margins stay even after folding.
- Impose a chosen page range instead of the whole document.
- Preview the full imposed booklet with on-demand side rendering, so long manuals stay responsive without building one huge in-memory PDF.
- Export the booklet as a PDF.
- Print from a simplified in-app final print sheet or open the native macOS print dialog.
- Configure paper preset (A3, A4, A5, B5, Letter, Legal, Tabloid, or custom size), scale mode, reading direction, margins, gutter, bleed, and landscape-page rotation.
- Add a blank first page or generated front cover.
- Add page numbering.
- Fine tune fold guide, cut marks, border style, border inset, and individual top, bottom, inside, and outside edges.
- Reset all settings to defaults with one click.
## Printing note

Bookleet generates the imposed PDF itself, then asks macOS to print it. The in-app final print sheet sets common options such as printer, copies, duplex, color, and quality where the selected printer driver supports those keys. The native dialog remains available for printer-specific controls.

For large documents, full export and print output is rendered directly to a PDF file instead of first building one huge in-memory PDF.

## Format note

PDFs are imposed directly because their page geometry is exact and stable. Word, Pages, and similar document formats need to be exported or printed to PDF first, then imported into Bookleet. That keeps booklet ordering and page boundaries identical to what the user expects from the source app.
