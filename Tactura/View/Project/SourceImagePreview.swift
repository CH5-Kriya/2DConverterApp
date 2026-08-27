import SwiftUI
import UIKit

/// The photograph a relief was made from, shown small beside it.
///
/// The workspace otherwise never shows the import again: once the pipeline has
/// run, the screen is all relief. Judging a conversion means comparing it with
/// what went in, and that comparison was only possible by leaving the screen.
struct SourceImageThumbnail: View {
    let image: UIImage
    let action: () -> Void

    /// Width comes from the column it sits in — the panel's 286 pt — so only
    /// the height is set here.
    static let height: CGFloat = 146

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            // The plate drives the layout and the photograph fills it, rather
            // than the other way round: a portrait import must not make this
            // slot taller than the design's 146 pt.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .background(Theme.Palette.white)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Original image")
        .accessibilityHint("Opens the photo this relief was made from")
    }
}

/// The same photograph at full size, over a dimmed workspace.
struct SourceImagePopup: View {
    let image: UIImage
    let onDismiss: () -> Void

    private static let maxWidth: CGFloat = 776
    private static let maxHeight: CGFloat = 490
    private static let radius: CGFloat = 39
    private static let border: CGFloat = 2.5

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // Matches the dialog the rest of the app dims with, rather than a
            // second scrim a shade apart from it.
            Theme.Palette.canvas.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(.isButton)

            // Fitted rather than filled. The thumbnail crops because it is a
            // thumbnail; this is the one place the whole import is on screen,
            // and cropping it here would defeat the reason for opening it.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
                .background(Theme.Palette.white)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white, lineWidth: Self.border) }
                .padding(32)
                .accessibilityLabel("Original image")
                .onTapGesture(perform: onDismiss)
        }
    }
}
