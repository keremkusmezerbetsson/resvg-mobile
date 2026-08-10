import Foundation
import UIKit
import SwiftUI
import ResvgMobile

/// In-memory LRU for rendered bitmaps.
final class ResvgImageCache {
    static let shared = ResvgImageCache(capacity: 64)

    private let capacity: Int
    private var keys: [String] = []
    private var values: [String: UIImage] = [:]
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func image(for key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard let image = values[key] else { return nil }
        if let idx = keys.firstIndex(of: key) {
            keys.remove(at: idx)
            keys.append(key)
        }
        return image
    }

    func set(_ image: UIImage, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if values[key] == nil {
            keys.append(key)
        }
        values[key] = image
        while keys.count > capacity {
            let oldest = keys.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }

    static func key(svgHash: Int, width: Int, height: Int, fit: FitMode, scale: CGFloat) -> String {
        "\(svgHash)|\(width)x\(height)|\(fit)|\(scale)"
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

    private var workItem: DispatchWorkItem?
    private let renderQueue = DispatchQueue(label: "com.resvg.mobile.render", qos: .userInitiated)

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                scheduleRender()
            }
        }
    }

    private func scheduleRender() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.renderNow() }
        workItem = item
        renderQueue.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func renderNow() {
        guard let data = svgData, bounds.width > 0, bounds.height > 0 else {
            DispatchQueue.main.async { self.image = nil }
            return
        }

        let pixelW = max(1, Int((bounds.width * renderScale).rounded()))
        let pixelH = max(1, Int((bounds.height * renderScale).rounded()))
        let cacheKey = ResvgImageCache.key(
            svgHash: data.hashValue,
            width: pixelW,
            height: pixelH,
            fit: fit,
            scale: renderScale
        )

        if let cached = ResvgImageCache.shared.image(for: cacheKey) {
            DispatchQueue.main.async { self.image = cached }
            return
        }

        let options = RenderOptions(
            width: UInt32(pixelW),
            height: UInt32(pixelH),
            fit: fit,
            background: nil
        )

        do {
            let uiImage = try Resvg.renderUIImage(data: data, options: options, scale: renderScale)
            ResvgImageCache.shared.set(uiImage, for: cacheKey)
            DispatchQueue.main.async { self.image = uiImage }
        } catch {
            DispatchQueue.main.async { self.image = nil }
        }
    }
}

/// SwiftUI wrapper around `ResvgImageView` behavior.
public struct ResvgImage: View {
    private let data: Data
    private let fit: FitMode
    private let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var size: CGSize = .zero

    public init(data: Data, fit: FitMode = .contain, contentMode: ContentMode = .fit) {
        self.data = data
        self.fit = fit
        self.contentMode = contentMode
    }

    public init?(named name: String, bundle: Bundle = .main, fit: FitMode = .contain, contentMode: ContentMode = .fit) {
        guard let url = bundle.url(forResource: name, withExtension: "svg"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        self.init(data: data, fit: fit, contentMode: contentMode)
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
                    .onAppear { size = geo.size; render(in: geo.size) }
                    .onChange(of: geo.size.width) { _ in
                        size = geo.size
                        render(in: geo.size)
                    }
                    .onChange(of: geo.size.height) { _ in
                        size = geo.size
                        render(in: geo.size)
                    }
            }
        )
    }

    private func render(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = UIScreen.main.scale
        let pixelW = max(1, Int((size.width * scale).rounded()))
        let pixelH = max(1, Int((size.height * scale).rounded()))
        let cacheKey = ResvgImageCache.key(
            svgHash: data.hashValue,
            width: pixelW,
            height: pixelH,
            fit: fit,
            scale: scale
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
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = try? Resvg.renderUIImage(data: svg, options: options, scale: scale)
            if let rendered {
                ResvgImageCache.shared.set(rendered, for: cacheKey)
            }
            DispatchQueue.main.async {
                self.image = rendered
            }
        }
    }
}
