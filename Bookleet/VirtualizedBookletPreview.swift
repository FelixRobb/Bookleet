import SwiftUI

struct VirtualizedBookletPreview: View {
    let model: BookletPreviewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(Array(model.sides.enumerated()), id: \.offset) { index, side in
                    BookletSidePreviewRow(
                        side: side,
                        image: model.renderedImages[index],
                        isLoading: model.loadingSides.contains(index)
                    )
                    .task(id: taskID(for: index)) {
                        model.loadSide(at: index)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func taskID(for index: Int) -> String {
        "\(model.generation)-\(index)"
    }
}

private struct BookletSidePreviewRow: View {
    let side: ImposedSheetSide
    let image: NSImage?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sideLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                }
            }
            .aspectRatio(sideAspectRatio, contentMode: .fit)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var sideLabel: String {
        let face = side.isFront ? "Front" : "Back"
        return "Sheet \(side.sheetNumber) · \(face)"
    }

    private var sideAspectRatio: CGFloat {
        let frames = side.placements.map(\.frame)
        guard
            let minX = frames.map(\.minX).min(),
            let maxX = frames.map(\.maxX).max(),
            let minY = frames.map(\.minY).min(),
            let maxY = frames.map(\.maxY).max(),
            maxY > 0
        else {
            return 1.414
        }

        let width = maxX + minX
        let height = maxY + minY
        return width / height
    }
}
