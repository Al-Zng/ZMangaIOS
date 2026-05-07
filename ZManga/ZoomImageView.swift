// ZoomableImageView.swift

import SwiftUI

struct ZoomableImageView: UIViewRepresentable {
    let url: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        Task {
            await context.coordinator.loadImage(url: url)
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if let img = context.coordinator.loadedImage {
            context.coordinator.imageView?.image = img
            context.coordinator.imageView?.frame = CGRect(origin: .zero, size: img.size)
            uiView.contentSize = img.size
            let scale = min(uiView.bounds.width / img.size.width, uiView.bounds.height / img.size.height, 1)
            uiView.zoomScale = scale
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        var imageView: UIImageView?
        var loadedImage: UIImage?

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        @MainActor
        func loadImage(url: String) async {
            if url.hasPrefix("http"), let imgURL = URL(string: url) {
                do {
                    let img = try await CachedAsyncImage.fetchImage(for: imgURL)
                    self.loadedImage = img
                    self.imageView?.image = img
                    if let scrollView = imageView?.superview as? UIScrollView {
                        scrollView.contentSize = img.size
                        let scale = min(scrollView.bounds.width / img.size.width, scrollView.bounds.height / img.size.height, 1)
                        scrollView.zoomScale = scale
                    }
                } catch {
                    // ignore
                }
            } else {
                if let img = UIImage(contentsOfFile: url) {
                    self.loadedImage = img
                    imageView?.image = img
                    if let scrollView = imageView?.superview as? UIScrollView {
                        scrollView.contentSize = img.size
                        let scale = min(scrollView.bounds.width / img.size.width, scrollView.bounds.height / img.size.height, 1)
                        scrollView.zoomScale = scale
                    }
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}