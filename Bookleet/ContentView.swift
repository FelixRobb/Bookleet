import AppKit
import ApplicationServices
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var loadedDocument: LoadedDocument?
    @State private var settings = BookletSettings()
    @State private var printSettings = PrintSettings()
    @State private var previewModel = BookletPreviewModel()
    @State private var errorMessage: String?
    @State private var isImporterPresented = false
    @State private var isShowingBorderEdges = false
    @State private var isPreparingFullOutput = false
    @State private var isPrintSheetPresented = false
    @State private var isDropTargeted = false

    private var hasDocument: Bool {
        loadedDocument != nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            previewPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Open", systemImage: "doc.badge.plus")
                }
                .help("Open document (⌘O)")

                Button {
                    exportBooklet()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasDocument)
                .help("Export PDF (⌘E)")

                Button {
                    prepareFinalPrint()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .disabled(!hasDocument)
                .help("Final print (⌘P)")
            }
        }
        .focusedSceneValue(\.bookleetActions, BookleetActions(
            openDocument: { isImporterPresented = true },
            exportPDF: { exportBooklet() },
            finalPrint: { prepareFinalPrint() },
            nativePrint: { runFinalPrint(showNativeDialog: true) },
            resetSettings: { settings = BookletSettings() },
            canExport: hasDocument,
            canPrint: hasDocument
        ))
        .focusedSceneValue(\.drawFoldGuide, $settings.drawFoldGuide)
        .focusedSceneValue(\.drawCutMarks, $settings.drawCutMarks)
        .focusedSceneValue(\.showPreviewBorders, $settings.showPageBordersInPreview)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: DocumentLoader.supportedTypes) { result in
            handleImport(result)
        }
        .alert("Bookleet", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isPrintSheetPresented) {
            FinalPrintView(
                settings: $printSettings,
                printerNames: NSPrinter.printerNames,
                onPrint: { runFinalPrint(showNativeDialog: false) },
                onNativePrint: { runFinalPrint(showNativeDialog: true) }
            )
            .frame(width: 460)
        }
        .onChange(of: settings) { _, _ in
            refreshPreview()
        }
        .onDisappear {
            previewModel.cancelRenderTasks()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                documentSection
                layoutSection
                spacingSection
                bindingSection
                pagesSection
                marksSection
                actionSection
            }
            .padding(20)
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bookleet")
                    .font(.largeTitle.bold())
                Text("Print-ready booklets with correct saddle-stitch ordering.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                settings = BookletSettings()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset all settings to defaults")
        }
    }

    private var documentSection: some View {
        SettingsGroup(title: "Document", systemImage: "doc.text") {
            Button {
                isImporterPresented = true
            } label: {
                Label(loadedDocument == nil ? "Choose Document" : "Replace Document", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let loadedDocument {
                LabeledContent("File", value: loadedDocument.displayName)
                LabeledContent("Pages", value: "\(loadedDocument.pageCount)")
                LabeledContent("Booklet pages", value: "\(BookletImposer.paddedPageCount(sourcePageCount: loadedDocument.pageCount, settings: settings))")
            } else {
                Text("Drop a PDF or image here, or choose one. Word and Pages files should be exported to PDF first so their pagination stays exact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var layoutSection: some View {
        SettingsGroup(title: "Layout", systemImage: "rectangle.portrait") {
            Picker("Paper", selection: $settings.paperPreset) {
                ForEach(PaperPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            if settings.paperPreset == .custom {
                HStack(spacing: 10) {
                    LabeledNumberField(title: "Width", value: $settings.customPaperWidth, range: 72...3000)
                    LabeledNumberField(title: "Height", value: $settings.customPaperHeight, range: 72...3000)
                }
            }

            Picker("Scale", selection: $settings.scaleMode) {
                ForEach(ScaleMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Picker("Reading", selection: $settings.readingDirection) {
                ForEach(ReadingDirection.allCases) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            Toggle("Rotate landscape pages to fit", isOn: $settings.rotatePagesToFit)
        }
    }

    private var spacingSection: some View {
        SettingsGroup(title: "Spacing", systemImage: "arrow.left.and.right") {
            SliderRow(title: "Margin", value: $settings.margin, range: 0...72, suffix: "pt")
            SliderRow(title: "Gutter", value: $settings.gutter, range: 0...48, suffix: "pt")
            SliderRow(title: "Bleed", value: $settings.pageBleed, range: -18...18, suffix: "pt")
        }
    }

    private var bindingSection: some View {
        SettingsGroup(title: "Binding", systemImage: "book.closed") {
            StepperRow(
                title: "Sheets per signature",
                value: $settings.sheetsPerSignature,
                range: 0...50,
                display: settings.sheetsPerSignature == 0 ? "Single fold" : "\(settings.sheetsPerSignature)"
            )
            Text(settings.sheetsPerSignature == 0
                 ? "All sheets nested into one fold. Best for thin booklets."
                 : "Split into bound signatures of \(settings.sheetsPerSignature) sheet\(settings.sheetsPerSignature == 1 ? "" : "s") each. Better for thick documents.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SliderRow(title: "Creep compensation", value: $settings.creep, range: 0...24, suffix: "pt")
            Text("Shifts inner pages toward the spine so fore-edge margins stay even after folding.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pagesSection: some View {
        SettingsGroup(title: "Pages", systemImage: "doc.on.doc") {
            Picker("First page", selection: $settings.openingPageMode) {
                ForEach(OpeningPageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if settings.openingPageMode == .titleCover {
                TextField("Cover title", text: $settings.titleCoverText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Limit page range", isOn: $settings.usePageRange)
            if settings.usePageRange {
                HStack(spacing: 10) {
                    LabeledIntField(title: "From", value: $settings.pageRangeStart, range: 1...max(1, sourcePageCount))
                    LabeledIntField(title: "To", value: $settings.pageRangeEnd, range: 1...max(1, sourcePageCount))
                }
            }

            Picker("Numbering", selection: $settings.pageNumberPlacement) {
                ForEach(PageNumberPlacement.allCases) { placement in
                    Text(placement.rawValue).tag(placement)
                }
            }

            if settings.pageNumberPlacement != .none {
                Stepper("Start at \(settings.pageNumberStart)", value: $settings.pageNumberStart, in: 0...9999)
                Toggle("Number inserted blank pages", isOn: $settings.numberBlankPages)
            }
        }
    }

    private var marksSection: some View {
        SettingsGroup(title: "Marks & Borders", systemImage: "scissors") {
            Toggle("Fold guide", isOn: $settings.drawFoldGuide)
            if settings.drawFoldGuide {
                SliderRow(title: "Fold width", value: $settings.foldGuideWidth, range: 0.2...3, suffix: "pt")
                Picker("Fold style", selection: $settings.foldGuideStyle) {
                    ForEach(BorderLineStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
            Toggle("Cut marks", isOn: $settings.drawCutMarks)
            Toggle("Show in preview", isOn: $settings.showPageBordersInPreview)
                    Text("Page borders are preview guides only and are omitted from exported PDFs and printing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

            DisclosureGroup("Page borders", isExpanded: $isShowingBorderEdges) {
                VStack(alignment: .leading, spacing: 12) {
                    SliderRow(title: "Border width", value: $settings.borderWidth, range: 0...4, suffix: "pt")
                    SliderRow(title: "Border inset", value: $settings.borderInset, range: -12...24, suffix: "pt")
                    Picker("Line style", selection: $settings.borderStyle) {
                        ForEach(BorderLineStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    Toggle("Top edge", isOn: $settings.drawTopEdge)
                    Toggle("Bottom edge", isOn: $settings.drawBottomEdge)
                    Toggle("Inside edge", isOn: $settings.drawInsideEdge)
                    Toggle("Outside edge", isOn: $settings.drawOutsideEdge)
                }
                .padding(.top, 8)
            }
        }
    }

    private var actionSection: some View {
        SettingsGroup(title: "Output", systemImage: "square.and.arrow.up") {
            Button {
                exportBooklet()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loadedDocument == nil)

            Button {
                prepareFinalPrint()
            } label: {
                Label("Final Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
            }
            .disabled(loadedDocument == nil)

            Button {
                runFinalPrint(showNativeDialog: true)
            } label: {
                Label("Native Print Dialog", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .disabled(loadedDocument == nil)
        }
    }

    private var sourcePageCount: Int {
        loadedDocument?.pageCount ?? 1
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview")
                        .font(.title3.bold())
                    Text(previewSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPreparingFullOutput {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            if loadedDocument == nil {
                ContentUnavailableView("Choose a PDF", systemImage: "doc.richtext", description: Text("Drop a PDF or image here, or use Choose Document."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                VirtualizedBookletPreview(model: previewModel)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else {
                return false
            }
            return importDocument(at: url)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var previewSubtitle: String {
        guard let loadedDocument else {
            return "No document loaded"
        }
        let sheetCount = BookletImposer.paddedPageCount(sourcePageCount: loadedDocument.pageCount, settings: settings) / 4
        return "\(sheetCount) sheet\(sheetCount == 1 ? "" : "s"), \(sheetCount * 2) printed side\(sheetCount == 1 ? "" : "s")"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            _ = importDocument(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func importDocument(at url: URL) -> Bool {
        do {
            loadedDocument = try DocumentLoader.load(url: url)
            refreshPreview()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshPreview() {
        previewModel.update(document: loadedDocument, settings: settings)
    }

    private func exportBooklet() {
        guard loadedDocument != nil else {
            errorMessage = BookletError.missingDocument.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultExportName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        renderFullOutput(destinationURL: url) { _ in
            await MainActor.run {}
        }
    }

    private func prepareFinalPrint() {
        if printSettings.printerName.isEmpty, let firstPrinter = NSPrinter.printerNames.first {
            printSettings.printerName = firstPrinter
        }
        isPrintSheetPresented = true
    }

    private func runFinalPrint(showNativeDialog: Bool) {
        guard loadedDocument != nil else {
            errorMessage = BookletError.missingDocument.localizedDescription
            return
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bookleet-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        renderFullOutput(destinationURL: temporaryURL) { url in
            await MainActor.run {
                guard let document = PDFDocument(url: url) else {
                    errorMessage = BookletError.renderingFailed.localizedDescription
                    return
                }

                runPrintOperation(document: document, showNativeDialog: showNativeDialog)
            }
        }
    }

    private func runPrintOperation(document: PDFDocument, showNativeDialog: Bool) {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.orientation = .landscape
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0

        if !printSettings.printerName.isEmpty, let printer = NSPrinter(name: printSettings.printerName) {
            printInfo.printer = printer
        }

        let dictionary = printInfo.dictionary()
        dictionary[NSPrintInfo.AttributeKey.copies] = printSettings.copies
        dictionary[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.spool.rawValue
        dictionary[NSPrintInfo.AttributeKey(rawValue: "NSPrintColor")] = printSettings.colorMode == .color
        dictionary[NSPrintInfo.AttributeKey(rawValue: "NSPrintQuality")] = printSettings.quality.printValue

        applyDuplexSetting(to: printInfo, twoSided: printSettings.twoSided)

        let operation = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false)
        operation?.showsPrintPanel = showNativeDialog || printSettings.showNativeDialog
        operation?.showsProgressPanel = true
        operation?.run()
        isPrintSheetPresented = false
    }

    private func renderFullOutput(destinationURL: URL, completion: @escaping @Sendable (URL) async -> Void) {
        guard let loadedDocument else {
            errorMessage = BookletError.missingDocument.localizedDescription
            return
        }

        let settingsSnapshot = settings
        let renderSource = loadedDocument.renderSource
        isPreparingFullOutput = true

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BookletImposer.renderFile(source: renderSource, settings: settingsSnapshot, destinationURL: destinationURL)
                }.value

                await completion(destinationURL)
                await MainActor.run {
                    isPreparingFullOutput = false
                }
            } catch {
                await MainActor.run {
                    isPreparingFullOutput = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var defaultExportName: String {
        let base = loadedDocument?.url.deletingPathExtension().lastPathComponent ?? "Booklet"
        return "\(base)-booklet.pdf"
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value, specifier: "%.1f") \(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}


private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let display: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct LabeledNumberField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .onChange(of: value) { _, newValue in
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }
        }
    }
}

private struct LabeledIntField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .onChange(of: value) { _, newValue in
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }
        }
    }
}

private struct FinalPrintView: View {
    @Binding var settings: PrintSettings
    let printerNames: [String]
    let onPrint: () -> Void
    let onNativePrint: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Final Print")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker("Printer", selection: $settings.printerName) {
                    if printerNames.isEmpty {
                        Text("System default").tag("")
                    } else {
                        ForEach(printerNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Stepper("Copies: \(settings.copies)", value: $settings.copies, in: 1...99)

                Picker("Color", selection: $settings.colorMode) {
                    ForEach(PrintColorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Quality", selection: $settings.quality) {
                    ForEach(PrintQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }

                Toggle("Two-sided, flip on short edge", isOn: $settings.twoSided)
                Toggle("Show native dialog before printing", isOn: $settings.showNativeDialog)
            }

            Text("Booklets should be printed two-sided and flipped on the short edge. Some printers expose color, duplex, and quality through their own driver panel, so use the native dialog when those choices matter.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Native Dialog") {
                    onNativePrint()
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Print") {
                    onPrint()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .onAppear {
            if settings.printerName.isEmpty, let firstPrinter = printerNames.first {
                settings.printerName = firstPrinter
            }
        }
    }
}

private func applyDuplexSetting(to printInfo: NSPrintInfo, twoSided: Bool) {
    let mode: PMDuplexMode = twoSided ? PMDuplexMode(kPMDuplexTumble) : PMDuplexMode(kPMDuplexNone)
    let settings = OpaquePointer(printInfo.pmPrintSettings())
    if PMSetDuplex(settings, mode) == noErr {
        printInfo.updateFromPMPrintSettings()
    }
}
