import Foundation
import UIKit
import SwiftUI
import ResvgMobile

/// In-memory LRU for rendered bitmaps, bounded by approximate byte cost.
final class ResvgImageCache {
    static let shared = ResvgImageCache(maxBytes: 32 * 1024 * 1024)

    private let maxBytes: Int
    private var keys: [String] = []
    private var values: [String: Entry] = [:]
    private var totalBytes: Int = 0
    private let lock = NSLock()

    private struct Entry {
        let image: UIImage
        let bytes: Int
    }

    init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    func image(for key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = values[key] else { return nil }
        if let idx = keys.firstIndex(of: key) {
            keys.remove(at: idx)
            keys.append(key)
        }
        return entry.image
    }

    func set(_ image: UIImage, for key: String) {
        lock.lock(); defer { lock.unlock() }
        let bytes = max(1, Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4)
        if let old = values[key] {
            totalBytes -= old.bytes
            keys.removeAll { $0 == key }
        }
        values[key] = Entry(image: image, bytes: bytes)
        keys.append(key)
        totalBytes += bytes
        while totalBytes > maxBytes, let oldest = keys.first {
            keys.removeFirst()
            if let removed = values.removeValue(forKey: oldest) {
                totalBytes -= removed.bytes
            }
        }
    }

    static func key(
        digest: String,
        width: Int,
        height: Int,
        fit: FitMode,
        scale: CGFloat,
        fonts: FontConfig
    ) -> String {
        "\(digest)|\(width)x\(height)|\(fit)|\(scale)|\(fonts.cacheSignature)"
    }
}

/// UIKit image view that rasterizes SVG off the main thread.
public final class ResvgImageView: UIImageView {
    public var svgData: Data? {
        didSet { scheduleRender() }
    }

    public var fit: FitMode = .contain {
        didSet { scheduleRender() }
    }

    public var renderScale: CGFloat = UIScreen.main.scale {
        didSet { scheduleRender() }
    }

    public var fonts: FontConfig = .empty {
        didSet { scheduleRender() }
    }

    private var workItem: DispatchWorkItem?
    private var generation: UInt64 = 0
    private let renderQueue = DispatchQueue(label: "com.resvg.mobile.render", qos: .userInitiated)

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                scheduleRender()
            }
        }
    }

    private func scheduleRender() {
        generation &+= 1
        let gen = generation
        workItem?.cancel()

        // Snapshot UIKit state on the main thread.
        let data = svgData
        let boundsSize = bounds.size
        let scale = renderScale
        let fitMode = fit
        let fonts = fonts

        guard let data else {
            image = nil
            return
        }
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.renderNow(
                data: data,
                boundsSize: boundsSize,
                scale: scale,
                fit: fitMode,
                fonts: fonts,
                generation: gen
            )
        }
        workItem = item
        renderQueue.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func renderNow(
        data: Data,
        boundsSize: CGSize,
        scale: CGFloat,
        fit: FitMode,
        fonts: FontConfig,
        generation: UInt64
    ) {
        let maxEdge = Resvg.uiMaxRenderEdge
        let pixelW = max(1, min(Int((boundsSize.width * scale).rounded()), maxEdge))
        let pixelH = max(1, min(Int((boundsSize.height * scale).rounded()), maxEdge))
        let digest = Resvg.contentDigest(data)
        let cacheKey = ResvgImageCache.key(
            digest: digest,
            width: pixelW,
            height: pixelH,
            fit: fit,
            scale: scale,
            fonts: fonts
        )

        if let cached = ResvgImageCache.shared.image(for: cacheKey) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.image = cached
            }
            return
        }

        let options = RenderOptions(
            width: UInt32(pixelW),
            height: UInt32(pixelH),
            fit: fit,
            background: nil
        )

        do {
            let uiImage = try Resvg.renderUIImage(
                data: data,
                options: options,
                scale: scale,
                fonts: fonts
            )
            ResvgImageCache.shared.set(uiImage, for: cacheKey)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.image = uiImage
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.image = nil
            }
        }
    }
}

/// SwiftUI wrapper around `ResvgImageView` behavior.
public struct ResvgImage: View {
    private let data: Data
    private let fit: FitMode
    private let contentMode: ContentMode
    private let fonts: FontConfig

    @State private var image: UIImage?
    @State private var renderGeneration: UInt64 = 0

    public init(
        data: Data,
        fit: FitMode = .contain,
        contentMode: ContentMode = .fit,
        fonts: FontConfig = .empty
    ) {
        self.data = data
        self.fit = fit
        self.contentMode = contentMode
        self.fonts = fonts
    }

    public init?(
        named name: String,
        bundle: Bundle = .main,
        fit: FitMode = .contain,
        contentMode: ContentMode = .fit,
        fonts: FontConfig = .empty
    ) {
        guard let url = bundle.url(forResource: name, withExtension: "svg"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        self.init(data: data, fit: fit, contentMode: contentMode, fonts: fonts)
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { render(in: geo.size) }
                    .onChange(of: geo.size.width) { _ in render(in: geo.size) }
                    .onChange(of: geo.size.height) { _ in render(in: geo.size) }
            }
        )
    }

    private func render(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        renderGeneration &+= 1
        let gen = renderGeneration
        let scale = UIScreen.main.scale
        let maxEdge = Resvg.uiMaxRenderEdge
        let pixelW = max(1, min(Int((size.width * scale).rounded()), maxEdge))
        let pixelH = max(1, min(Int((size.height * scale).rounded()), maxEdge))
        let digest = Resvg.contentDigest(data)
        let cacheKey = ResvgImageCache.key(
            digest: digest,
            width: pixelW,
            height: pixelH,
            fit: fit,
            scale: scale,
            fonts: fonts
        )
        if let cached = ResvgImageCache.shared.image(for: cacheKey) {
            self.image = cached
            return
        }

        let options = RenderOptions(
            width: UInt32(pixelW),
            height: UInt32(pixelH),
            fit: fit,
            background: nil
        )
        let svg = data
        let fontConfig = fonts
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = try? Resvg.renderUIImage(
                data: svg,
                options: options,
                scale: scale,
                fonts: fontConfig
            )
            if let rendered {
                ResvgImageCache.shared.set(rendered, for: cacheKey)
            }
            DispatchQueue.main.async {
                guard gen == renderGeneration else { return }
                self.image = rendered
            }
        }
    }
}
