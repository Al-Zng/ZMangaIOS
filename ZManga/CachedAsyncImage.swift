import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?

    private static let cache = URLCache(
        memoryCapacity: 50 * 1024 * 1024,  // 50 MB
        diskCapacity: 200 * 1024 * 1024,   // 200 MB
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    )
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else if isLoading {
                Rectangle()
                    .fill(Color(white: 0.1))
                    .overlay(
                        ProgressView()
                            .tint(ZTheme.accent)
                    )
            } else {
                Rectangle()
                    .fill(Color(white: 0.1))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    )
            }
        }
        .task {
            guard let url = url else { return }
            do {
                let (data, _) = try await session.data(from: url)
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                } else {
                    error = URLError(.cannotDecodeContentData)
                }
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }
}