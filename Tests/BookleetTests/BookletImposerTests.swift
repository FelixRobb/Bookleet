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
}
