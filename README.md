# Bookleet

Bookleet is a native macOS SwiftUI app for turning ordinary PDFs into print-ready booklet PDFs.

## Run in Xcode

1. Open `Package.swift` in Xcode.
2. Select the `Bookleet` executable scheme.
3. Press Run.

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
