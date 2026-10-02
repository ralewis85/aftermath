import SwiftUI

struct StreamArtwork: View {
    let stream: IPTVStream
    let size: CGFloat

    var body: some View {
        Group {
            if let logoURL = stream.logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.gray.opacity(0.3)))
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(String(stream.name.prefix(2)).uppercased())
            .font(.system(size: size * 0.32, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
    }
}
