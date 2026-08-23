import SwiftUI

struct HeroArtworkView: View {
    var body: some View {
        Image("HeroArtwork")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

#Preview {
    HeroArtworkView()
        .padding(60)
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
