import SwiftUI
import UIKit

/// Two-level image cache: decoded images in memory (NSCache) plus raw bytes on disk
/// (a dedicated 500 MB URLCache). Covers load once and stay put when you move between pages.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    // NSCache is thread-safe; in-flight de-duplication lives in an actor.
    private let memory: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()
    private let session: URLSession
    private let loader = Loader()

    private actor Loader {
        var inFlight: [URL: Task<UIImage?, Never>] = [:]
        func task(for url: URL, make: @Sendable @escaping () async -> UIImage?) -> Task<UIImage?, Never> {
            if let t = inFlight[url] { return t }
            let t = Task { await make() }
            inFlight[url] = t
            return t
        }
        func finish(_ url: URL) { inFlight[url] = nil }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        let session = self.session, memory = self.memory
        let task = await loader.task(for: url) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await session.data(for: request),
                  let image = UIImage(data: data) else { return nil }
            let decoded = image.preparingForDisplay() ?? image
            memory.setObject(decoded, forKey: url as NSURL, cost: data.count)
            return decoded
        }
        let result = await task.value
        await loader.finish(url)
        return result
    }

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// Drop-in replacement for AsyncImage that uses ImageCache. Shows instantly when cached.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageCache.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.image(for: url)
            withAnimation(.easeIn(duration: 0.15)) { image = loaded }
        }
    }

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }
}

struct Avatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 36

    var body: some View {
        CachedImage(url: url) {
            Circle().fill(.quaternary)
                .overlay(Text(String(name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Full-screen zoomable cover

struct CoverViewer: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var dragOffset: CGFloat = 0
    @State private var zoomed = false

    private var backdropOpacity: Double {
        let fade: Double = Double(abs(dragOffset)) / 400.0
        return 1.0 - min(fade, 0.6)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            if let image {
                ZoomableImage(image: image, isZoomed: $zoomed)
                    .ignoresSafeArea()
                    .offset(y: dragOffset)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in if !zoomed { dragOffset = v.translation.height } }
                            .onEnded { v in
                                if !zoomed && abs(v.translation.height) > 120 { dismiss() }
                                else { withAnimation(.spring) { dragOffset = 0 } }
                            }
                    )
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding()
            .opacity(abs(dragOffset) > 10 ? 0 : 1)
        }
        .statusBarHidden()
        .task { image = await ImageCache.shared.image(for: url) }
    }
}

/// UIScrollView-backed pinch / double-tap zoom.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        iv.frame = scroll.bounds
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(iv)
        context.coordinator.imageView = iv
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage
        weak var imageView: UIImageView?
        init(_ parent: ZoomableImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            if parent.isZoomed != zoomed { parent.isZoomed = zoomed }
        }

        @objc func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: imageView)
                let scale: CGFloat = 3
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
