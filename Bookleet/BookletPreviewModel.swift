import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BookletPreviewModel {
    private(set) var sides: [ImposedSheetSide] = []
    private(set) var renderedImages: [Int: NSImage] = [:]
    private(set) var loadingSides: Set<Int> = []
    private(set) var generation = 0

    private var renderSource: BookletRenderSource?
    private var settings = BookletSettings()
    private var renderTasks: [Int: Task<Void, Never>] = [:]
    private let imageCache = NSCache<NSNumber, NSImage>()

    init() {
        imageCache.countLimit = 48
    }

    func update(document: LoadedDocument?, settings: BookletSettings) {
        generation += 1
        cancelRenderTasks()
        renderedImages = [:]
        loadingSides = []
        imageCache.removeAllObjects()

        guard let document else {
            sides = []
            renderSource = nil
            return
        }

        renderSource = document.renderSource
        self.settings = settings
        sides = BookletImposer.sheetSides(sourcePageCount: document.pageCount, settings: settings)
    }

    func loadSide(at index: Int) {
        guard index >= 0, index < sides.count else {
            return
        }

        if renderedImages[index] != nil {
            return
        }

        if let cached = imageCache.object(forKey: NSNumber(value: index)) {
            renderedImages[index] = cached
            return
        }

        if loadingSides.contains(index) || renderTasks[index] != nil {
            return
        }

        guard let renderSource else {
            return
        }

        loadingSides.insert(index)
        let side = sides[index]
        let settingsSnapshot = settings
        let currentGeneration = generation

        renderTasks[index] = Task {
            do {
                let imageData = try await Task.detached(priority: .userInitiated) {
                    let image = try BookletImposer.renderSideImage(
                        source: renderSource,
                        settings: settingsSnapshot,
                        side: side
                    )
                    guard let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw BookletError.renderingFailed
                    }
                    return png
                }.value

                guard !Task.isCancelled, currentGeneration == generation else {
                    return
                }

                guard let image = NSImage(data: imageData) else {
                    loadingSides.remove(index)
                    renderTasks[index] = nil
                    return
                }

                imageCache.setObject(image, forKey: NSNumber(value: index))
                renderedImages[index] = image
                loadingSides.remove(index)
                renderTasks[index] = nil
            } catch {
                guard !Task.isCancelled, currentGeneration == generation else {
                    return
                }
                loadingSides.remove(index)
                renderTasks[index] = nil
            }
        }
    }

    func cancelRenderTasks() {
        for task in renderTasks.values {
            task.cancel()
        }
        renderTasks = [:]
    }
}
