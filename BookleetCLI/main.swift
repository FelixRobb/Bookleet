import Foundation

do {
    let configuration = try CLIConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
    let document = try DocumentLoader.load(url: configuration.inputURL)
    var settings = configuration.settings
    settings.pageRangeEnd = max(settings.pageRangeStart, min(settings.pageRangeEnd, document.pageCount))

    try BookletImposer.renderFile(
        source: document.renderSource,
        settings: settings,
        destinationURL: configuration.outputURL
    )

    if configuration.verbose {
        let sheets = BookletImposer.sheetSides(sourcePageCount: document.pageCount, settings: settings).count
        fputs("Wrote \(configuration.outputURL.path) (\(sheets) sheet side\(sheets == 1 ? "" : "s"))\n", stderr)
    }
} catch is CLIHelpRequested {
    exit(0)
} catch let error as CLIError {
    fputs("bookleet: \(error.message)\n", stderr)
    if case .usage = error {
        fputs("\n\(CLIConfiguration.helpText)\n", stderr)
    }
    exit(error.exitCode)
} catch {
    fputs("bookleet: \(error.localizedDescription)\n", stderr)
    exit(1)
}

struct CLIHelpRequested: Error {}

enum CLIError: Error {
    case usage(String)
    case runtime(String)

    var message: String {
        switch self {
        case .usage(let message), .runtime(let message):
            message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage:
            2
        case .runtime:
            1
        }
    }
}

struct CLIConfiguration {
    let inputURL: URL
    let outputURL: URL
    let settings: BookletSettings
    let verbose: Bool

    static let helpText = """
    USAGE:
      bookleet [options] <input>

    ARGUMENTS:
      <input>                 Source PDF or image to impose

    OPTIONS:
      -o, --output <path>     Output PDF path (default: <input>-booklet.pdf)
      -h, --help              Show this help

      --paper <preset>        Paper size: a3, a4, a5, b5, letter, legal, tabloid, custom
      --paper-width <pt>      Custom paper width in points (with --paper custom)
      --paper-height <pt>     Custom paper height in points (with --paper custom)
      --margin <pt>           Page margin (default: 18)
      --gutter <pt>           Gutter between pages (default: 10)
      --bleed <pt>            Page bleed (default: 0)
      --scale <mode>          fit or fill (default: fit)
      --reading <dir>         ltr or rtl (default: ltr)
      --no-rotate             Do not rotate landscape pages to fit

      --sheets-per-signature <n>
                              Sheets per signature; 0 = single fold (default: 0)
      --creep <pt>            Creep compensation (default: 0)

      --page-range <start>-<end>
                              Impose only this 1-based page range
      --first-page <mode>     document, blank, or cover (default: document)
      --cover-title <text>    Title for generated front cover

      --page-numbers <place>  none, center, outside, or inside (default: none)
      --page-number-start <n> Starting page number (default: 1)

      --fold-guide / --no-fold-guide
      --cut-marks / --no-cut-marks
      -v, --verbose           Print summary to stderr

    EXAMPLES:
      bookleet document.pdf
      bookleet -o booklet.pdf --paper a4 --margin 12 manual.pdf
      bookleet --page-range 3-20 --page-numbers outside report.pdf
    """

    init(arguments: [String]) throws {
        var settings = BookletSettings()
        var inputPath: String?
        var outputPath: String?
        var verbose = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                print(Self.helpText)
                throw CLIHelpRequested()

            case "-v", "--verbose":
                verbose = true

            case "-o", "--output":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for \(argument)")
                }
                outputPath = value

            case "--paper":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --paper")
                }
                settings.paperPreset = try Self.parsePaperPreset(value)

            case "--paper-width":
                settings.customPaperWidth = try Self.parseDouble(iterator.next(), flag: argument)

            case "--paper-height":
                settings.customPaperHeight = try Self.parseDouble(iterator.next(), flag: argument)

            case "--margin":
                settings.margin = try Self.parseDouble(iterator.next(), flag: argument)

            case "--gutter":
                settings.gutter = try Self.parseDouble(iterator.next(), flag: argument)

            case "--bleed":
                settings.pageBleed = try Self.parseDouble(iterator.next(), flag: argument)

            case "--scale":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --scale")
                }
                settings.scaleMode = try Self.parseScaleMode(value)

            case "--reading":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --reading")
                }
                settings.readingDirection = try Self.parseReadingDirection(value)

            case "--no-rotate":
                settings.rotatePagesToFit = false

            case "--sheets-per-signature":
                settings.sheetsPerSignature = try Self.parseInt(iterator.next(), flag: argument)

            case "--creep":
                settings.creep = try Self.parseDouble(iterator.next(), flag: argument)

            case "--page-range":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --page-range")
                }
                try Self.applyPageRange(value, to: &settings)

            case "--first-page":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --first-page")
                }
                settings.openingPageMode = try Self.parseOpeningPageMode(value)

            case "--cover-title":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --cover-title")
                }
                settings.titleCoverText = value

            case "--page-numbers":
                guard let value = iterator.next() else {
                    throw CLIError.usage("Missing value for --page-numbers")
                }
                settings.pageNumberPlacement = try Self.parsePageNumberPlacement(value)

            case "--page-number-start":
                settings.pageNumberStart = try Self.parseInt(iterator.next(), flag: argument)

            case "--fold-guide":
                settings.drawFoldGuide = true

            case "--no-fold-guide":
                settings.drawFoldGuide = false

            case "--cut-marks":
                settings.drawCutMarks = true

            case "--no-cut-marks":
                settings.drawCutMarks = false

            case let value where value.hasPrefix("-"):
                throw CLIError.usage("Unknown option \(value)")

            default:
                if inputPath != nil {
                    throw CLIError.usage("Unexpected argument \(argument)")
                }
                inputPath = argument
            }
        }

        guard let inputPath else {
            throw CLIError.usage("Missing input file")
        }

        let resolvedInput = URL(fileURLWithPath: inputPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedInput.path) else {
            throw CLIError.runtime("Input file does not exist: \(resolvedInput.path)")
        }

        let resolvedOutput: URL
        if let outputPath {
            resolvedOutput = URL(fileURLWithPath: outputPath).standardizedFileURL
        } else {
            resolvedOutput = resolvedInput
                .deletingPathExtension()
                .appendingPathComponent(resolvedInput.deletingPathExtension().lastPathComponent + "-booklet")
                .appendingPathExtension("pdf")
        }

        self.inputURL = resolvedInput
        self.outputURL = resolvedOutput
        self.settings = settings
        self.verbose = verbose
    }

    private static func parsePaperPreset(_ value: String) throws -> PaperPreset {
        switch value.lowercased() {
        case "a3": .a3
        case "a4": .a4
        case "a5": .a5
        case "b5": .b5
        case "letter": .letter
        case "legal": .legal
        case "tabloid": .tabloid
        case "custom": .custom
        default:
            throw CLIError.usage("Unknown paper preset: \(value)")
        }
    }

    private static func parseScaleMode(_ value: String) throws -> ScaleMode {
        switch value.lowercased() {
        case "fit": .fit
        case "fill": .fill
        default:
            throw CLIError.usage("Unknown scale mode: \(value)")
        }
    }

    private static func parseReadingDirection(_ value: String) throws -> ReadingDirection {
        switch value.lowercased() {
        case "ltr", "left-to-right", "left": .leftToRight
        case "rtl", "right-to-left", "right": .rightToLeft
        default:
            throw CLIError.usage("Unknown reading direction: \(value)")
        }
    }

    private static func parseOpeningPageMode(_ value: String) throws -> OpeningPageMode {
        switch value.lowercased() {
        case "document", "first": .documentFirst
        case "blank": .blankFirst
        case "cover", "title": .titleCover
        default:
            throw CLIError.usage("Unknown first-page mode: \(value)")
        }
    }

    private static func parsePageNumberPlacement(_ value: String) throws -> PageNumberPlacement {
        switch value.lowercased() {
        case "none", "off": .none
        case "center", "centred", "bottom-center": .centeredBottom
        case "outside", "bottom-outside": .outsideBottom
        case "inside", "bottom-inside": .insideBottom
        default:
            throw CLIError.usage("Unknown page-number placement: \(value)")
        }
    }

    private static func applyPageRange(_ value: String, to settings: inout BookletSettings) throws {
        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start >= 1,
              end >= start else {
            throw CLIError.usage("Page range must look like start-end, e.g. 3-20")
        }
        settings.usePageRange = true
        settings.pageRangeStart = start
        settings.pageRangeEnd = end
    }

    private static func parseDouble(_ value: String?, flag: String) throws -> Double {
        guard let value, let number = Double(value) else {
            throw CLIError.usage("Missing or invalid value for \(flag)")
        }
        return number
    }

    private static func parseInt(_ value: String?, flag: String) throws -> Int {
        guard let value, let number = Int(value) else {
            throw CLIError.usage("Missing or invalid value for \(flag)")
        }
        return number
    }
}
