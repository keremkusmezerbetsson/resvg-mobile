import Foundation
import UIKit

// Generated UniFFI Swift lives alongside this file under Generated/.

public enum Resvg {
    /// Default iOS system font directories for text-bearing SVGs.
    public static var defaultFontDirs: [String] {
        [
            "/System/Library/Fonts",
            "/System/Library/Fonts/Core",
            "/System/Library/Fonts/Supplemental",
        ]
    }

    /// Render SVG bytes to a `UIImage`. Prefer calling off the main thread for large SVGs.
    public static func renderUIImage(
        data: Data,
        options: RenderOptions = RenderOptions(width: nil, height: nil, fit: .contain, background: nil),
        scale: CGFloat = UIScreen.main.scale,
        fontDirs: [String] = []
    ) throws -> UIImage {
        let rendered: RenderedImage
        if fontDirs.isEmpty {
            rendered = try render(svg: data, options: options)
        } else {
            rendered = try renderWithFonts(svg: data, options: options, fontDirs: fontDirs)
        }
        return try rendered.uiImage(scale: scale)
    }

    public static func measure(data: Data) throws -> CGSize {
        let size = try intrinsicSize(svg: data)
        return CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
    }
}

public extension RenderedImage {
    /// Convert straight RGBA bytes to `UIImage`.
    func uiImage(scale: CGFloat = UIScreen.main.scale) throws -> UIImage {
        let w = Int(width)
        let h = Int(height)
        guard w > 0, h > 0, rgba.count == w * h * 4 else {
            throw ResvgError.InvalidSize(message: "invalid RGBA buffer")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        var premul = [UInt8](repeating: 0, count: rgba.count)
        rgba.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: src.count, by: 4) {
                let r = src[i]
                let g = src[i + 1]
                let b = src[i + 2]
                let a = src[i + 3]
                if a == 0 {
                    continue
                } else if a == 255 {
                    premul[i] = r
                    premul[i + 1] = g
                    premul[i + 2] = b
                    premul[i + 3] = a
                } else {
                    premul[i] = UInt8((Int(r) * Int(a) + 127) / 255)
                    premul[i + 1] = UInt8((Int(g) * Int(a) + 127) / 255)
                    premul[i + 2] = UInt8((Int(b) * Int(a) + 127) / 255)
                    premul[i + 3] = a
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(premul) as CFData),
              let cgImage = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            throw ResvgError.Render(message: "failed to create CGImage")
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
