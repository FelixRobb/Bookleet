import AppKit
import PDFKit
import Testing
@testable import Bookleet

struct PageNumberRenderTests {
    @Test func numbersAppearInRenderedSide() throws {
        let pdfData = makePDF(pageCount: 8)
        let source = PDFDocument(data: pdfData)!

        var settings = BookletSettings()
        settings.pageNumberPlacement = .centeredBottom

        let sides = BookletImposer.sheetSides(sourcePageCount: source.pageCount, settings: settings)
        let image = try BookletImposer.renderSideImage(source: source, settings: settings, side: sides[0], scale: 2)

        #expect(darkPixelCount(in: image) > 0)
    }

    @Test func titleCoverAppearsInRenderedSide() throws {
        let pdfData = makePDF(pageCount: 8)
        let source = PDFDocument(data: pdfData)!

        var settings = BookletSettings()
        settings.openingPageMode = .titleCover

        let sides = BookletImposer.sheetSides(sourcePageCount: source.pageCount, settings: settings)
        let image = try BookletImposer.renderSideImage(source: source, settings: settings, side: sides[0], scale: 2)

        #expect(darkPixelCount(in: image) > 0)
    }

    private func makePDF(pageCount: Int) -> Data {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func darkPixelCount(in image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }
        var count = 0
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.brightnessComponent < 0.7 {
                    count += 1
                }
            }
        }
        return count
    }
}
