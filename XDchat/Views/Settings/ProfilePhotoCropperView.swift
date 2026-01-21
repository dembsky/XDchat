import SwiftUI
import AppKit

struct ProfilePhotoCropperView: View {
    let image: NSImage
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropSize: CGFloat = 200
    private let outputSize: CGFloat = 200

    var body: some View {
        VStack(spacing: 20) {
            Text("Adjust Profile Photo")
                .font(.headline)
                .padding(.top, 16)

            Text("Drag to position, scroll to zoom")
                .font(.caption)
                .foregroundColor(.secondary)

            // Simple circular crop preview
            ZStack {
                Color.gray.opacity(0.3)

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cropSize * scale, height: cropSize * scale)
                    .offset(offset)
                    .clipShape(Circle())

                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: cropSize, height: cropSize)
            }
            .frame(width: cropSize + 40, height: cropSize + 40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )

            // Zoom slider
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.secondary)

                Slider(value: $scale, in: 0.5...3.0)
                    .frame(width: 180)

                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.secondary)
            }

            // Buttons
            HStack(spacing: 20) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let croppedData = cropImage() {
                        onSave(croppedData)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(width: 320, height: 420)
        .background(Color(.windowBackgroundColor))
    }

    private func cropImage() -> Data? {
        // Create a circular cropped image
        let finalImage = NSImage(size: NSSize(width: outputSize, height: outputSize))
        finalImage.lockFocus()

        // Clip to circle
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: outputSize, height: outputSize))
        circlePath.addClip()

        // Calculate source rect based on scale and offset
        let imageSize = image.size
        let baseScale = max(outputSize / imageSize.width, outputSize / imageSize.height)
        let effectiveScale = baseScale * scale

        let scaledWidth = imageSize.width * effectiveScale
        let scaledHeight = imageSize.height * effectiveScale

        let offsetX = (scaledWidth - outputSize) / 2 - offset.width
        let offsetY = (scaledHeight - outputSize) / 2 + offset.height // Flip Y for AppKit

        // Draw image
        image.draw(
            in: NSRect(x: -offsetX, y: -offsetY, width: scaledWidth, height: scaledHeight),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0
        )

        finalImage.unlockFocus()

        // Convert to JPEG
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }

        return jpegData
    }
}

#Preview {
    ProfilePhotoCropperView(
        image: NSImage(named: NSImage.folderName)!,
        onSave: { _ in },
        onCancel: {}
    )
}
