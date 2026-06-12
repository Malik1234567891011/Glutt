import SwiftUI

/// Renders a recipe's image from whichever source it has:
/// bundled asset, picked photo data, remote URL, or a placeholder.
struct RecipeImageView: View {
    let recipe: Recipe

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                // .clipped() only clips drawing — the scaledToFill image still
                // hit-tests far outside its frame, stealing taps from views
                // above/below the card. The image is decorative, so opt it out.
                .allowsHitTesting(false)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var content: some View {
        if let assetName = recipe.imageAssetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let urlString = recipe.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.Colors.accent.opacity(0.08))
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.accent.opacity(0.35))
        }
    }
}
