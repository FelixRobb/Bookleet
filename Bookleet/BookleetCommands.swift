import SwiftUI

struct BookleetActions {
    var openDocument: () -> Void = {}
    var exportPDF: () -> Void = {}
    var finalPrint: () -> Void = {}
    var nativePrint: () -> Void = {}
    var resetSettings: () -> Void = {}
    var canExport = false
    var canPrint = false
}

private struct BookleetActionsKey: FocusedValueKey {
    typealias Value = BookleetActions
    static var defaultValue: BookleetActions? { nil }
}

private struct DrawFoldGuideKey: FocusedValueKey {
    typealias Value = Binding<Bool>
    static var defaultValue: Binding<Bool>? { nil }
}

private struct DrawCutMarksKey: FocusedValueKey {
    typealias Value = Binding<Bool>
    static var defaultValue: Binding<Bool>? { nil }
}

private struct ShowPreviewBordersKey: FocusedValueKey {
    typealias Value = Binding<Bool>
    static var defaultValue: Binding<Bool>? { nil }
}

extension FocusedValues {
    var bookleetActions: BookleetActions? {
        get { self[BookleetActionsKey.self] }
        set { self[BookleetActionsKey.self] = newValue }
    }

    var drawFoldGuide: Binding<Bool>? {
        get { self[DrawFoldGuideKey.self] }
        set { self[DrawFoldGuideKey.self] = newValue }
    }

    var drawCutMarks: Binding<Bool>? {
        get { self[DrawCutMarksKey.self] }
        set { self[DrawCutMarksKey.self] = newValue }
    }

    var showPreviewBorders: Binding<Bool>? {
        get { self[ShowPreviewBordersKey.self] }
        set { self[ShowPreviewBordersKey.self] = newValue }
    }
}

struct BookleetCommands: Commands {
    @FocusedValue(\.bookleetActions) private var actions
    @FocusedValue(\.drawFoldGuide) private var drawFoldGuide
    @FocusedValue(\.drawCutMarks) private var drawCutMarks
    @FocusedValue(\.showPreviewBorders) private var showPreviewBorders

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                actions?.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Export PDF…") {
                actions?.exportPDF()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(actions?.canExport != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Final Print…") {
                actions?.finalPrint()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(actions?.canPrint != true)

            Button("Native Print Dialog…") {
                actions?.nativePrint()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(actions?.canPrint != true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Reset All Settings") {
                actions?.resetSettings()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Toggle("Fold Guide", isOn: drawFoldGuide ?? .constant(false))
                .keyboardShortcut("f", modifiers: [.command, .control])
                .disabled(drawFoldGuide == nil)

            Toggle("Cut Marks", isOn: drawCutMarks ?? .constant(false))
                .keyboardShortcut("m", modifiers: [.command, .control])
                .disabled(drawCutMarks == nil)

            Toggle("Preview Borders", isOn: showPreviewBorders ?? .constant(false))
                .keyboardShortcut("b", modifiers: [.command, .control])
                .disabled(showPreviewBorders == nil)
        }
    }
}
