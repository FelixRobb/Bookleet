import Foundation
import PDFKit
import UniformTypeIdentifiers

struct LoadedDocument {
    let url: URL
    let pdf: PDFDocument
    let renderSource: BookletRenderSource

    var displayName: String {
        url.lastPathComponent
    }

    var pageCount: Int {
        pdf.pageCount
    }
}

enum DocumentLoader {
    static let supportedTypes: [UTType] = [
        .pdf,
        .rtf,
        .rtfd,
        .plainText,
        .image,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "pages") ?? .data
    ]

    static func load(url: URL) throws -> LoadedDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            throw BookletError.unsupportedDocument("Could not identify this document type.")
        }

        if type.conforms(to: .pdf), let pdf = PDFDocument(url: url), pdf.pageCount > 0 {
            return LoadedDocument(url: url, pdf: pdf, renderSource: .file(url))
        }

        if type.conforms(to: .image), let imagePDF = PDFDocument.singlePageImagePDF(url: url) {
            guard let data = imagePDF.dataRepresentation() else {
                throw BookletError.renderingFailed
            }
            return LoadedDocument(url: url, pdf: imagePDF, renderSource: .data(data))
        }

        throw BookletError.unsupportedDocument("Bookleet can impose PDFs directly. For Word, Pages, and other paged documents, export or print them to PDF first, then import that PDF.")
    }
}

enum BookletError: LocalizedError {
    case missingDocument
    case unsupportedDocument(String)
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .missingDocument:
            "Choose a document first."
        case .unsupportedDocument(let message):
            message
        case .renderingFailed:
            "The booklet PDF could not be rendered."
        }
    }
}
