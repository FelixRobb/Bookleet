import AppKit
import PDFKit
import Testing
@testable import Bookleet

struct BookletImposerTests {
    @Test func imposesEightPagesInSaddleStitchOrder() {
        let sides = BookletImposer.sheetSides(sourcePageCount: 8, settings: BookletSettings())

        #expect(sides.count == 4)
        #expect(pageNumbers(on: sides[0]) == [8, 1])
        #expect(pageNumbers(on: sides[1]) == [2, 7])
        #expect(pageNumbers(on: sides[2]) == [6, 3])
        #expect(pageNumbers(on: sides[3]) == [4, 5])
    }

    @Test func padsShortDocumentsToCompleteSheets() {
        let sides = BookletImposer.sheetSides(sourcePageCount: 5, settings: BookletSettings())

        #expect(sides.count == 4)
        #expect(pageNumbers(on: sides[0]) == [nil, 1])
        #expect(pageNumbers(on: sides[1]) == [2, nil])
        #expect(pageNumbers(on: sides[2]) == [nil, 3])
        #expect(pageNumbers(on: sides[3]) == [4, 5])
    }

    @Test func blankFirstPageIsIncludedBeforeImposition() {
        var settings = BookletSettings()
        settings.openingPageMode = .blankFirst

        let sides = BookletImposer.sheetSides(sourcePageCount: 3, settings: settings)

        #expect(sides.count == 2)
        #expect(pageNumbers(on: sides[0]) == [3, nil])
        #expect(pageNumbers(on: sides[1]) == [1, 2])
    }

    @Test func splitsIntoSignaturesOfRequestedSheetCount() {
        var settings = BookletSettings()
        settings.sheetsPerSignature = 1

        let sides = BookletImposer.sheetSides(sourcePageCount: 8, settings: settings)

        #expect(sides.count == 4)
        #expect(pageNumbers(on: sides[0]) == [4, 1])
        #expect(pageNumbers(on: sides[1]) == [2, 3])
        #expect(pageNumbers(on: sides[2]) == [8, 5])
        #expect(pageNumbers(on: sides[3]) == [6, 7])
        #expect(sides[0].sheetNumber == 1)
        #expect(sides[2].sheetNumber == 2)
    }

    @Test func foldGuideAlignsOnFrontAndBackOfSameSheet() throws {
        let source = PDFDocument(data: makePDF(pageCount: 8))!
        var settings = BookletSettings()
        settings.drawFoldGuide = true
        settings.foldGuideWidth = 2

        let sides = BookletImposer.sheetSides(sourcePageCount: source.pageCount, settings: settings)
        let front = try BookletImposer.renderSideImage(source: source, settings: settings, side: sides[0], scale: 2)
        let back = try BookletImposer.renderSideImage(source: source, settings: settings, side: sides[1], scale: 2)

        let frontFoldX = try #require(foldGuideX(in: front))
        let backFoldX = try #require(foldGuideX(in: back))

        #expect(abs(frontFoldX - backFoldX) < 2)
        #expect(abs(frontFoldX - (front.size.width / 2)) < 4)
    }

    @Test func imposesOnlySelectedPageRange() {
        var settings = BookletSettings()
        settings.usePageRange = true
        settings.pageRangeStart = 3
        settings.pageRangeEnd = 6

        let sides = BookletImposer.sheetSides(sourcePageCount: 10, settings: settings)

        #expect(sides.count == 2)
        #expect(pageNumbers(on: sides[0]) == [6, 3])
        #expect(pageNumbers(on: sides[1]) == [4, 5])
    }

    private func pageNumbers(on side: ImposedSheetSide) -> [Int?] {
        side.placements.map { placement in
            placement.sourcePageIndex.map { $0 + 1 }
        }
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

    private func foldGuideX(in image: NSImage) -> CGFloat? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var columnScores = [Int](repeating: 0, count: width)

        for y in stride(from: height / 4, to: (height * 3) / 4, by: 2) {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.brightnessComponent < 0.8 {
                    columnScores[x] += 1
                }
            }
        }

        guard let peak = columnScores.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 else {
            return nil
        }

        return CGFloat(peak.offset) / CGFloat(max(width - 1, 1)) * image.size.width
    }
}
