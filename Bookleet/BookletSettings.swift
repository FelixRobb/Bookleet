import CoreGraphics
import Foundation

enum PaperPreset: String, CaseIterable, Identifiable, Sendable {
    case a3 = "A3"
    case a4 = "A4"
    case a5 = "A5"
    case b5 = "B5"
    case letter = "Letter"
    case legal = "Legal"
    case tabloid = "Tabloid"
    case custom = "Custom"

    var id: String { rawValue }

    /// Single-page portrait size in points, or `nil` for `.custom` (resolved from settings).
    var defaultPortraitSize: CGSize? {
        switch self {
        case .a3:
            CGSize(width: 841.89, height: 1190.55)
        case .a4:
            CGSize(width: 595.28, height: 841.89)
        case .a5:
            CGSize(width: 419.53, height: 595.28)
        case .b5:
            CGSize(width: 498.90, height: 708.66)
        case .letter:
            CGSize(width: 612, height: 792)
        case .legal:
            CGSize(width: 612, height: 1008)
        case .tabloid:
            CGSize(width: 792, height: 1224)
        case .custom:
            nil
        }
    }
}

enum ScaleMode: String, CaseIterable, Identifiable, Sendable {
    case fit = "Fit"
    case fill = "Fill"

    var id: String { rawValue }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Sendable {
    case leftToRight = "Left to right"
    case rightToLeft = "Right to left"

    var id: String { rawValue }
}

enum OpeningPageMode: String, CaseIterable, Identifiable, Sendable {
    case documentFirst = "Document first"
    case blankFirst = "Blank first page"
    case titleCover = "Generated front page"

    var id: String { rawValue }
}

enum PageNumberPlacement: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case centeredBottom = "Bottom center"
    case outsideBottom = "Bottom outside"
    case insideBottom = "Bottom inside"

    var id: String { rawValue }
}

enum BorderLineStyle: String, CaseIterable, Identifiable, Sendable {
    case solid = "Solid"
    case dashed = "Dashed"
    case dotted = "Dotted"

    var id: String { rawValue }
}

enum PrintColorMode: String, CaseIterable, Identifiable, Sendable {
    case color = "Color"
    case blackAndWhite = "Black & white"

    var id: String { rawValue }
}

enum PrintQuality: String, CaseIterable, Identifiable, Sendable {
    case draft = "Draft"
    case normal = "Normal"
    case best = "Best"

    var id: String { rawValue }

    var printValue: Int {
        switch self {
        case .draft:
            -1
        case .normal:
            0
        case .best:
            1
        }
    }
}

struct BookletSettings: Equatable, Sendable {
    var paperPreset: PaperPreset = .a4
    var customPaperWidth: Double = 595
    var customPaperHeight: Double = 842
    var margin: Double = 18
    var gutter: Double = 10
    var pageBleed: Double = 0
    var borderWidth: Double = 0.5
    var borderInset: Double = 0
    var borderStyle: BorderLineStyle = .solid
    var showPageBordersInPreview = false
    var drawTopEdge = true
    var drawBottomEdge = true
    var drawInsideEdge = true
    var drawOutsideEdge = true
    var drawFoldGuide = false
    var foldGuideWidth: Double = 0.4
    var foldGuideStyle: BorderLineStyle = .solid
    var drawCutMarks = false
    var scaleMode: ScaleMode = .fit
    var readingDirection: ReadingDirection = .leftToRight
    var rotatePagesToFit = true
    var includeBlankPadding = true
    var sheetsPerSignature: Int = 0
    var creep: Double = 0
    var usePageRange = false
    var pageRangeStart: Int = 1
    var pageRangeEnd: Int = 1
    var openingPageMode: OpeningPageMode = .documentFirst
    var titleCoverText = "Booklet"
    var pageNumberPlacement: PageNumberPlacement = .none
    var pageNumberStart: Int = 1
    var numberBlankPages = false

    /// Resolved portrait paper size, honoring custom dimensions.
    var paperPortraitSize: CGSize {
        if let preset = paperPreset.defaultPortraitSize {
            return preset
        }
        return CGSize(width: max(72, customPaperWidth), height: max(72, customPaperHeight))
    }

    /// Resolved landscape sheet size used for two-up imposition.
    var paperLandscapeSize: CGSize {
        let size = paperPortraitSize
        return CGSize(width: max(size.width, size.height), height: min(size.width, size.height))
    }
}

struct PrintSettings: Equatable, Sendable {
    var printerName = ""
    var copies = 1
    var colorMode: PrintColorMode = .color
    var quality: PrintQuality = .normal
    var twoSided = true
    var showNativeDialog = false
}
