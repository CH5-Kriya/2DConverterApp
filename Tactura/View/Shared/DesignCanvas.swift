import SwiftUI

/// The app drawn at its design width and scaled to fill a phone's screen.
///
/// Every screen here is measured off a 1366 pt-wide iPad canvas — a 300 pt
/// sidebar, 64 pt gutters, 457 pt home cards, 20 pt body text — and those are
/// literal frames, not proportions. Nothing in the hierarchy reflows below
/// them, so on a 402 pt phone the layout does not shrink, it overflows: the
/// sidebar alone takes three quarters of the width and the cards run off the
/// edge. That overflow is what reads on screen as "zoomed in".
///
/// **Width only, deliberately.** Scaling to fit *both* axes is what put black
/// bars on the screen: a 4:3 canvas has no scale that fills a 19.5:9 phone, in
/// either orientation, so fitting it always leaves bands. Pinning the width
/// instead means the scale is always `screen width / 1366` and the canvas is
/// exactly as tall as the screen — full bleed, and the design's horizontal
/// proportions are kept intact.
///
/// What that trades away is vertical room. The canvas gets whatever height the
/// device's aspect gives it: in portrait about 2900 design pt, far more than
/// the 1024 the design assumes, and the surplus falls to the bottom because
/// every screen is top-aligned — the way it already does on a portrait iPad. In
/// landscape it is roughly 730, less than the design was drawn against, so a
/// screen taller than that clips at the bottom. Home needs about 670 and fits;
/// anything taller is the first thing to check when a screen changes.
///
/// That is the whole shape of the compromise: full bleed, undistorted, no
/// clipping — pick two. The third only arrives with a real compact layout, and
/// a phone does not want a 300 pt sidebar at any scale.
/// ponytail: width-scaled canvas, replace with per-screen compact layouts.
struct DesignCanvas<Content: View>: View {

    /// The width every screen in this app is measured against: iPad Pro
    /// 13-inch landscape.
    static var designWidth: CGFloat { 1366 }

    @ViewBuilder var content: () -> Content

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            scaled
        } else {
            content()
        }
    }

    /// Laid out at the design width, then scaled — not laid out at the phone's
    /// width. Fixing the frame first is the whole point: it keeps every child
    /// believing it has an iPad's room, so the proportions that come out are
    /// the design's rather than SwiftUI's best effort at squeezing them.
    ///
    /// The reader keeps its safe area deliberately. At the root of the scene
    /// its frame is already the safe area — measured as (0, 62, 402, 778) on a
    /// 402x874 iPhone — so its size is exactly the room the phone can show,
    /// the island and the corners subtracted, and the scale comes out right in
    /// both orientations without anything being told where a cutout is.
    ///
    /// Do not add the proxy's `safeAreaInsets` back as padding. The reader
    /// reports them even though its frame has already been inset by them, so
    /// padding by them insets the content a second time and the sidebar starts
    /// 124 pt down. Only the canvas colour ignores the safe area, which is what
    /// carries the background into the status bar and home-indicator strips and
    /// makes the screen read as full bleed while the layout stays inside it.
    ///
    /// **Known defect.** The sidebar's wordmark and its Hide Menu button draw
    /// roughly 20 pt above and below this canvas, so on a phone they sit under
    /// the status bar and the home indicator. The cause is the `NavigationStack`
    /// in `RootView`: it is UIKit-backed and sizes itself from the window
    /// instead of from the frame proposed to it, so its children are laid out
    /// against the window's height and spill past the scaled bounds. Borders
    /// drawn on the canvas and on the content confirmed both boxes are correct
    /// and only the stack's children escape. Moving the canvas inside the stack
    /// was tried and is worse — the root renders twice. The two real fixes are
    /// a UIKit transform on the window's root view, which scales beneath the
    /// navigation controller where this problem cannot arise, or per-screen
    /// compact layouts.
    /// ponytail: known overlap, upgrade path is a window transform.
    private var scaled: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designWidth
            content()
                .environment(\.tacturaCanvasScale, scale)
                .frame(width: Self.designWidth, height: proxy.size.height / scale)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }
}
