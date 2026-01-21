import SwiftUI

struct ProfileAvatarView: View {
    let imageData: Data
    let initials: String
    let size: CGFloat

    init(imageData: Data, initials: String, size: CGFloat = Constants.UI.mediumAvatarSize) {
        self.imageData = imageData
        self.initials = initials
        self.size = size
    }

    private var circularImage: NSImage? {
        guard !imageData.isEmpty, let sourceImage = NSImage(data: imageData) else {
            return nil
        }
        return Self.createCircularImage(from: sourceImage, size: size)
    }

    private static func createCircularImage(from source: NSImage, size: CGFloat) -> NSImage {
        let outputSize = NSSize(width: size, height: size)
        let outputImage = NSImage(size: outputSize)

        outputImage.lockFocus()

        // Clip to circle
        let rect = NSRect(origin: .zero, size: outputSize)
        NSBezierPath(ovalIn: rect).addClip()

        // Calculate aspect fill
        let sourceSize = source.size
        let scale = max(size / sourceSize.width, size / sourceSize.height)
        let scaledWidth = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale
        let offsetX = (size - scaledWidth) / 2
        let offsetY = (size - scaledHeight) / 2

        // Draw
        source.draw(
            in: NSRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )

        outputImage.unlockFocus()
        return outputImage
    }

    var body: some View {
        if let image = circularImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent)
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfileAvatarView(imageData: Data(), initials: "JD", size: 28)
        ProfileAvatarView(imageData: Data(), initials: "JD", size: 40)
        ProfileAvatarView(imageData: Data(), initials: "JD", size: 80)
    }
    .padding()
}
