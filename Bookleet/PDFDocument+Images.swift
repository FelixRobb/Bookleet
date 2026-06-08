import AppKit
import PDFKit

extension PDFDocument {
    static func singlePageImagePDF(url: URL) -> PDFDocument? {
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            return nil
        }

        let size = image.size == .zero ? CGSize(width: 612, height: 792) : image.size
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: mediaBox)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return PDFDocument(data: data as Data)
    }
}
