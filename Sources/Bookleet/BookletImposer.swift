import AppKit
import CoreGraphics
import Foundation
import PDFKit

enum BookletRenderSource: Sendable {
    case file(URL)
    case data(Data)
}

enum BookletPageContent: Equatable, Sendable {
    case source(Int)
    case blank
    case title(String)

    var sourcePageIndex: Int? {
        if case .source(let index) = self {
            return index
        }
        return nil
    }
}

struct ImposedPagePlacement: Identifiable, Equatable {
    let id = UUID()
    let content: BookletPageContent
    let frame: CGRect

    var sourcePageIndex: Int? {
        content.sourcePageIndex
    }
}

struct ImposedSheetSide: Identifiable, Equatable {
    let id = UUID()
    let sheetNumber: Int
    let isFront: Bool
    let placements: [ImposedPagePlacement]
}

enum BookletImposer {
    // Semantic AppKit colors (e.g. secondaryLabelColor) resolve to white in offscreen contexts.
    private static let pageNumberColor = NSColor(white: 0.45, alpha: 1)
    private static let titleCoverColor = NSColor.black
    private static let subtitleCoverColor = NSColor(white: 0.45, alpha: 1)
    private static let borderStrokeColor = NSColor(white: 0.65, alpha: 1).cgColor
    private static let guideStrokeColor = NSColor(white: 0.75, alpha: 1).cgColor

    static func sheetSides(sourcePageCount: Int, settings: BookletSettings) -> [ImposedSheetSide] {
        sheetSides(pages: pages(sourcePageCount: sourcePageCount, settings: settings), settings: settings)
    }

    static func sheetSides(pages: [BookletPageContent], settings: BookletSettings) -> [ImposedSheetSide] {
        let paddedPages = paddedPages(pages)
        let signatureSize = signaturePageCount(totalPaddedPages: paddedPages.count, settings: settings)

        var sides: [ImposedSheetSide] = []
        var completedSheets = 0
        var start = 0

        while start < paddedPages.count {
            let end = min(start + signatureSize, paddedPages.count)
            let signature = Array(paddedPages[start..<end])
            sides.append(contentsOf: imposeSignature(signature, settings: settings, startingSheetNumber: completedSheets + 1))
            completedSheets += signature.count / 4
            start = end
        }

        return sides
    }

    /// Number of pages in each signature (a multiple of 4). `0` sheets per signature means a single saddle-stitch fold.
    static func signaturePageCount(totalPaddedPages: Int, settings: BookletSettings) -> Int {
        guard settings.sheetsPerSignature > 0 else {
            return max(4, totalPaddedPages)
        }
        return max(4, settings.sheetsPerSignature * 4)
    }

    private static func imposeSignature(
        _ paddedPages: [BookletPageContent],
        settings: BookletSettings,
        startingSheetNumber: Int
    ) -> [ImposedSheetSide] {
        let paddedCount = paddedPages.count
        let paper = settings.paperLandscapeSize
        let safeMargin = CGFloat(settings.margin)
        let gutter = CGFloat(settings.gutter)
        let halfWidth = (paper.width - safeMargin * 2 - gutter) / 2
        let frameHeight = paper.height - safeMargin * 2
        let leftFrame = CGRect(x: safeMargin, y: safeMargin, width: halfWidth, height: frameHeight)
        let rightFrame = CGRect(x: safeMargin + halfWidth + gutter, y: safeMargin, width: halfWidth, height: frameHeight)
        let sheetCount = paddedCount / 4

        return (0..<sheetCount).flatMap { sheetIndex -> [ImposedSheetSide] in
            let frontLeft = paddedPages[paddedCount - (sheetIndex * 2) - 1]
            let frontRight = paddedPages[sheetIndex * 2]
            let backLeft = paddedPages[(sheetIndex * 2) + 1]
            let backRight = paddedPages[paddedCount - (sheetIndex * 2) - 2]

            let creep = creepOffset(forSheetIndex: sheetIndex, sheetCount: sheetCount, settings: settings)
            let creepedLeft = leftFrame.offsetBy(dx: creep, dy: 0)
            let creepedRight = rightFrame.offsetBy(dx: -creep, dy: 0)

            let front = makeSide(sheetNumber: startingSheetNumber + sheetIndex, isFront: true, left: frontLeft, right: frontRight, leftFrame: creepedLeft, rightFrame: creepedRight, settings: settings)
            let back = makeSide(sheetNumber: startingSheetNumber + sheetIndex, isFront: false, left: backLeft, right: backRight, leftFrame: creepedLeft, rightFrame: creepedRight, settings: settings)
            return [front, back]
        }
    }

    /// Inner sheets are nudged toward the spine to compensate for fore-edge push-out after folding.
    private static func creepOffset(forSheetIndex index: Int, sheetCount: Int, settings: BookletSettings) -> CGFloat {
        guard settings.creep > 0, sheetCount > 1 else {
            return 0
        }
        let fraction = CGFloat(index) / CGFloat(sheetCount - 1)
        return CGFloat(settings.creep) * fraction
    }

    static func render(source: PDFDocument, settings: BookletSettings) throws -> PDFDocument {
        guard let data = source.dataRepresentation() else {
            throw BookletError.renderingFailed
        }
        guard let document = PDFDocument(data: try renderData(sourceData: data, settings: settings)) else {
            throw BookletError.renderingFailed
        }
        return document
    }

    static func renderData(source: BookletRenderSource, settings: BookletSettings, maxSides: Int? = nil) throws -> Data {
        let document = try openDocument(source)
        return try renderData(source: document, settings: settings, maxSides: maxSides)
    }

    static func renderFile(source: BookletRenderSource, settings: BookletSettings, destinationURL: URL, maxSides: Int? = nil) throws {
        let document = try openDocument(source)
        try renderFile(source: document, settings: settings, destinationURL: destinationURL, maxSides: maxSides)
    }

    static func renderData(sourceData: Data, settings: BookletSettings) throws -> Data {
        guard let source = PDFDocument(data: sourceData) else {
            throw BookletError.renderingFailed
        }

        return try renderData(source: source, settings: settings)
    }

    private static func renderData(source: PDFDocument, settings: BookletSettings, maxSides: Int? = nil) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw BookletError.renderingFailed
        }

        try render(source: source, settings: settings, consumer: consumer, maxSides: maxSides)

        return data as Data
    }

    private static func renderFile(source: PDFDocument, settings: BookletSettings, destinationURL: URL, maxSides: Int? = nil) throws {
        guard let consumer = CGDataConsumer(url: destinationURL as CFURL) else {
            throw BookletError.renderingFailed
        }

        try render(source: source, settings: settings, consumer: consumer, maxSides: maxSides)
    }

    static func renderSideImage(
        source: BookletRenderSource,
        settings: BookletSettings,
        side: ImposedSheetSide,
        scale: CGFloat = 2
    ) throws -> NSImage {
        let document = try openDocument(source)
        return try renderSideImage(source: document, settings: settings, side: side, scale: scale)
    }

    static func renderSideImage(
        source: PDFDocument,
        settings: BookletSettings,
        side: ImposedSheetSide,
        scale: CGFloat = 2
    ) throws -> NSImage {
        let mediaBox = CGRect(origin: .zero, size: settings.paperLandscapeSize)
        let pixelWidth = max(1, Int(mediaBox.width * scale))
        let pixelHeight = max(1, Int(mediaBox.height * scale))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BookletError.renderingFailed
        }

        context.scaleBy(x: scale, y: scale)
        drawSide(side, source: source, settings: settings, in: context, mediaBox: mediaBox, includePageBorders: settings.showPageBordersInPreview)

        guard let cgImage = context.makeImage() else {
            throw BookletError.renderingFailed
        }

        return NSImage(cgImage: cgImage, size: mediaBox.size)
    }

    private static func render(source: PDFDocument, settings: BookletSettings, consumer: CGDataConsumer, maxSides: Int? = nil) throws {
        let logicalPages = pages(sourcePageCount: source.pageCount, settings: settings)
        let allSides = sheetSides(pages: logicalPages, settings: settings)
        let sides = maxSides.map { Array(allSides.prefix($0)) } ?? allSides

        var mediaBox = CGRect(origin: .zero, size: settings.paperLandscapeSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BookletError.renderingFailed
        }

        for side in sides {
            context.beginPDFPage(nil)
            drawSide(side, source: source, settings: settings, in: context, mediaBox: mediaBox, includePageBorders: false)
            context.endPDFPage()
        }

        context.closePDF()
    }

    private static func drawSide(
        _ side: ImposedSheetSide,
        source: PDFDocument,
        settings: BookletSettings,
        in context: CGContext,
        mediaBox: CGRect,
        includePageBorders: Bool
    ) {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        drawGuides(in: context, mediaBox: mediaBox, settings: settings)

        for placement in side.placements {
            switch placement.content {
            case .source(let sourcePageIndex):
                guard let page = source.page(at: sourcePageIndex) else {
                    drawBlankPage(in: context, frame: placement.frame, settings: settings, includePageBorders: includePageBorders)
                    drawPageNumberIfNeeded(in: context, frame: placement.frame, placement: placement, side: side, settings: settings)
                    continue
                }
                draw(page: page, in: context, frame: placement.frame, settings: settings, includePageBorders: includePageBorders)
            case .blank:
                drawBlankPage(in: context, frame: placement.frame, settings: settings, includePageBorders: includePageBorders)
            case .title(let title):
                drawTitleCover(title: title, in: context, frame: placement.frame, settings: settings, includePageBorders: includePageBorders)
            }
            drawPageNumberIfNeeded(in: context, frame: placement.frame, placement: placement, side: side, settings: settings)
        }
    }

    private static func openDocument(_ source: BookletRenderSource) throws -> PDFDocument {
        let document: PDFDocument?

        switch source {
        case .file(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            document = PDFDocument(url: url)
        case .data(let data):
            document = PDFDocument(data: data)
        }

        guard let document else {
            throw BookletError.renderingFailed
        }

        return document
    }

    static func paddedPageCount(_ pageCount: Int) -> Int {
        max(4, Int(ceil(Double(pageCount) / 4.0)) * 4)
    }

    static func logicalPageCount(sourcePageCount: Int, settings: BookletSettings) -> Int {
        pages(sourcePageCount: sourcePageCount, settings: settings).count
    }

    static func paddedPageCount(sourcePageCount: Int, settings: BookletSettings) -> Int {
        paddedPageCount(logicalPageCount(sourcePageCount: sourcePageCount, settings: settings))
    }

    private static func makeSide(
        sheetNumber: Int,
        isFront: Bool,
        left: BookletPageContent,
        right: BookletPageContent,
        leftFrame: CGRect,
        rightFrame: CGRect,
        settings: BookletSettings
    ) -> ImposedSheetSide {
        let pair = settings.readingDirection == .leftToRight ? (left, right) : (right, left)
        return ImposedSheetSide(
            sheetNumber: sheetNumber,
            isFront: isFront,
            placements: [
                ImposedPagePlacement(content: pair.0, frame: leftFrame),
                ImposedPagePlacement(content: pair.1, frame: rightFrame)
            ]
        )
    }

    private static func pages(sourcePageCount: Int, settings: BookletSettings) -> [BookletPageContent] {
        var pages: [BookletPageContent] = []

        switch settings.openingPageMode {
        case .documentFirst:
            break
        case .blankFirst:
            pages.append(.blank)
        case .titleCover:
            pages.append(.title(settings.titleCoverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Booklet" : settings.titleCoverText))
        }

        pages.append(contentsOf: sourcePageRange(sourcePageCount: sourcePageCount, settings: settings).map(BookletPageContent.source))
        return pages
    }

    private static func sourcePageRange(sourcePageCount: Int, settings: BookletSettings) -> Range<Int> {
        guard settings.usePageRange, sourcePageCount > 0 else {
            return 0..<sourcePageCount
        }
        let lower = max(0, min(settings.pageRangeStart - 1, sourcePageCount - 1))
        let upper = max(lower, min(settings.pageRangeEnd - 1, sourcePageCount - 1))
        return lower..<(upper + 1)
    }

    private static func paddedPages(_ pages: [BookletPageContent]) -> [BookletPageContent] {
        let paddedCount = paddedPageCount(pages.count)
        return pages + Array(repeating: .blank, count: paddedCount - pages.count)
    }

    private static func draw(page: PDFPage, in context: CGContext, frame: CGRect, settings: BookletSettings, includePageBorders: Bool) {
        let bleed = CGFloat(settings.pageBleed)
        let drawingFrame = frame.insetBy(dx: bleed, dy: bleed)
        let pageBounds = page.bounds(for: .mediaBox)
        let sourceSize = pageBounds.size
        let targetSize = drawingFrame.size
        let shouldRotate = settings.rotatePagesToFit && sourceSize.width > sourceSize.height && targetSize.width < targetSize.height
        let normalizedSourceSize = shouldRotate ? CGSize(width: sourceSize.height, height: sourceSize.width) : sourceSize
        let scaleX = targetSize.width / normalizedSourceSize.width
        let scaleY = targetSize.height / normalizedSourceSize.height
        let scale = settings.scaleMode == .fit ? min(scaleX, scaleY) : max(scaleX, scaleY)
        let renderSize = CGSize(width: normalizedSourceSize.width * scale, height: normalizedSourceSize.height * scale)
        let renderOrigin = CGPoint(x: drawingFrame.midX - renderSize.width / 2, y: drawingFrame.midY - renderSize.height / 2)
        let renderRect = CGRect(origin: renderOrigin, size: renderSize)

        context.saveGState()
        context.clip(to: drawingFrame)
        context.translateBy(x: renderRect.minX, y: renderRect.minY)
        context.scaleBy(x: scale, y: scale)

        if shouldRotate {
            context.translateBy(x: 0, y: sourceSize.width)
            context.rotate(by: -.pi / 2)
        }

        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        drawPageEdges(in: context, frame: frame, settings: settings, includePageBorders: includePageBorders)
    }

    private static func drawBlankPage(in context: CGContext, frame: CGRect, settings: BookletSettings, includePageBorders: Bool) {
        drawPageEdges(in: context, frame: frame, settings: settings, includePageBorders: includePageBorders)
    }

    private static func drawTitleCover(title: String, in context: CGContext, frame: CGRect, settings: BookletSettings, includePageBorders: Bool) {
        drawBlankPage(in: context, frame: frame, settings: settings, includePageBorders: includePageBorders)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: titleCoverColor,
            .paragraphStyle: paragraphStyle
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: subtitleCoverColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleRect = CGRect(x: frame.minX + 28, y: frame.midY + 8, width: frame.width - 56, height: 44)
        let subtitleRect = CGRect(x: frame.minX + 28, y: frame.midY - 24, width: frame.width - 56, height: 20)

        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        title.draw(in: titleRect, withAttributes: attributes)
        "Front cover".draw(in: subtitleRect, withAttributes: subtitleAttributes)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func drawPageEdges(in context: CGContext, frame: CGRect, settings: BookletSettings, includePageBorders: Bool) {
        guard includePageBorders, settings.borderWidth > 0 else {
            return
        }

        let borderFrame = frame.insetBy(dx: CGFloat(settings.borderInset), dy: CGFloat(settings.borderInset))
        context.saveGState()
        context.setStrokeColor(borderStrokeColor)
        context.setLineWidth(CGFloat(settings.borderWidth))
        applyLineStyle(settings.borderStyle, width: CGFloat(settings.borderWidth), to: context)

        if settings.drawTopEdge {
            context.move(to: CGPoint(x: borderFrame.minX, y: borderFrame.maxY))
            context.addLine(to: CGPoint(x: borderFrame.maxX, y: borderFrame.maxY))
        }
        if settings.drawBottomEdge {
            context.move(to: CGPoint(x: borderFrame.minX, y: borderFrame.minY))
            context.addLine(to: CGPoint(x: borderFrame.maxX, y: borderFrame.minY))
        }
        if settings.drawInsideEdge {
            context.move(to: CGPoint(x: borderFrame.midX < settings.paperLandscapeSize.width / 2 ? borderFrame.maxX : borderFrame.minX, y: borderFrame.minY))
            context.addLine(to: CGPoint(x: borderFrame.midX < settings.paperLandscapeSize.width / 2 ? borderFrame.maxX : borderFrame.minX, y: borderFrame.maxY))
        }
        if settings.drawOutsideEdge {
            context.move(to: CGPoint(x: borderFrame.midX < settings.paperLandscapeSize.width / 2 ? borderFrame.minX : borderFrame.maxX, y: borderFrame.minY))
            context.addLine(to: CGPoint(x: borderFrame.midX < settings.paperLandscapeSize.width / 2 ? borderFrame.minX : borderFrame.maxX, y: borderFrame.maxY))
        }

        context.strokePath()
        context.restoreGState()
    }

    private static func drawGuides(in context: CGContext, mediaBox: CGRect, settings: BookletSettings) {
        context.saveGState()
        context.setStrokeColor(guideStrokeColor)
        context.setLineWidth(CGFloat(settings.foldGuideWidth))

        if settings.drawFoldGuide {
            applyLineStyle(settings.foldGuideStyle, width: CGFloat(settings.foldGuideWidth), to: context)
            context.move(to: CGPoint(x: mediaBox.midX, y: 0))
            context.addLine(to: CGPoint(x: mediaBox.midX, y: mediaBox.height))
            context.strokePath()
        }

        if settings.drawCutMarks {
            let length: CGFloat = 10
            let inset = CGFloat(settings.margin)
            let points = [
                CGPoint(x: inset, y: inset),
                CGPoint(x: mediaBox.width - inset, y: inset),
                CGPoint(x: inset, y: mediaBox.height - inset),
                CGPoint(x: mediaBox.width - inset, y: mediaBox.height - inset)
            ]
            for point in points {
                context.move(to: CGPoint(x: point.x - length, y: point.y))
                context.addLine(to: CGPoint(x: point.x + length, y: point.y))
                context.move(to: CGPoint(x: point.x, y: point.y - length))
                context.addLine(to: CGPoint(x: point.x, y: point.y + length))
            }
            context.strokePath()
        }

        context.restoreGState()
    }

    private static func drawPageNumberIfNeeded(
        in context: CGContext,
        frame: CGRect,
        placement: ImposedPagePlacement,
        side: ImposedSheetSide,
        settings: BookletSettings
    ) {
        guard settings.pageNumberPlacement != .none else {
            return
        }

        guard settings.numberBlankPages || placement.sourcePageIndex != nil else {
            return
        }

        let number: Int
        if let sourcePageIndex = placement.sourcePageIndex {
            number = settings.pageNumberStart + sourcePageIndex
        } else {
            number = settings.pageNumberStart
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: pageNumberColor,
            .paragraphStyle: paragraphStyle
        ]
        let width: CGFloat = 44
        let height: CGFloat = 16
        let y = frame.minY + 8
        let x: CGFloat

        switch settings.pageNumberPlacement {
        case .none:
            return
        case .centeredBottom:
            x = frame.midX - width / 2
        case .outsideBottom:
            x = frame.midX < settings.paperLandscapeSize.width / 2 ? frame.minX + 12 : frame.maxX - width - 12
        case .insideBottom:
            x = frame.midX < settings.paperLandscapeSize.width / 2 ? frame.maxX - width - 12 : frame.minX + 12
        }

        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        "\(number)".draw(in: CGRect(x: x, y: y, width: width, height: height), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func applyLineStyle(_ style: BorderLineStyle, width: CGFloat, to context: CGContext) {
        switch style {
        case .solid:
            context.setLineDash(phase: 0, lengths: [])
        case .dashed:
            context.setLineDash(phase: 0, lengths: [max(4, width * 5), max(3, width * 3)])
        case .dotted:
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [0.1, max(2, width * 3)])
        }
    }
}
