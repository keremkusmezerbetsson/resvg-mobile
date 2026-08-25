import Foundation
import UIKit
import CryptoKit

// Generated UniFFI Swift lives alongside this file under Generated/.

public enum Resvg {
    /// Soft edge cap used by UI wrappers. The Rust core enforces its own limits.
    public static let uiMaxRenderEdge: Int = 2048

    /// Suggested system font directories for text-bearing SVGs.
    /// Helpers default to `[]` for icons; pass these when rendering text.
    ///
    /// iOS does **not** ship Noto Sans / Amiri / Mplus. Suite SVGs that name
    /// those families still need bundled fonts (see `bundledFontDirs`).
    public static var systemFontDirs: [String] {
        [
            "/System/Library/Fonts",
            "/System/Library/Fonts/Core",
            "/System/Library/Fonts/Supplemental",
        ]
    }

    /// Directory of fonts copied into an app bundle (e.g. `suite-fonts`).
    public static func bundledFontDirs(
        in bundle: Bundle = .main,
        folder: String = "suite-fonts"
    ) -> [String] {
        guard let url = bundle.resourceURL?.appendingPathComponent(folder, isDirectory: true) else {
            return []
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        return [url.path]
    }

    /// Load `.ttf` / `.otf` / `.ttc` files from a bundle folder as raw font bytes.
    public static func bundledFontData(
        in bundle: Bundle = .main,
        folder: String = "suite-fonts"
    ) -> [Data] {
        guard let url = bundle.resourceURL?.appendingPathComponent(folder, isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
              )
        else {
            return []
        }
        let allowed: Set<String> = ["ttf", "otf", "ttc", "otc"]
        return files
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }
    }

    /// Common CSS / system family names → faces in the resvg-test-suite font set.
    public static let defaultFontAliases: [FontAlias] = [
        FontAlias(requested: "sans-serif", replacement: "Noto Sans"),
        FontAlias(requested: "serif", replacement: "Noto Serif"),
        FontAlias(requested: "monospace", replacement: "Noto Mono"),
        FontAlias(requested: "cursive", replacement: "Yellowtail"),
        FontAlias(requested: "fantasy", replacement: "Sedgwick Ave Display"),
        FontAlias(requested: "Arial", replacement: "Noto Sans"),
        FontAlias(requested: "Helvetica", replacement: "Noto Sans"),
        FontAlias(requested: "Helvetica Neue", replacement: "Noto Sans"),
        FontAlias(requested: "system-ui", replacement: "Noto Sans"),
        FontAlias(requested: "Times New Roman", replacement: "Noto Serif"),
        FontAlias(requested: "Courier New", replacement: "Noto Mono"),
    ]

    /// In-memory fonts + aliases. Prefer this on iOS over `bundledFontDirs`.
    public static func bundledFontConfig(
        in bundle: Bundle = .main,
        folder: String = "suite-fonts",
        aliases: [FontAlias] = defaultFontAliases,
        defaultFamily: String? = "Noto Sans"
    ) -> FontConfig {
        FontConfig(
            dirs: [],
            data: bundledFontData(in: bundle, folder: folder),
            aliases: aliases,
            defaultFamily: defaultFamily
        )
    }

    /// Render SVG bytes to a `UIImage`. Prefer calling off the main thread for large SVGs.
    ///
    /// Default fit is `.intrinsic` so a bare `renderUIImage(data:)` call succeeds.
    /// For `contain` / `cover` / `fill`, both width and height are required.
    public static func renderUIImage(
        data: Data,
        options: RenderOptions = RenderOptions(width: nil, height: nil, fit: .intrinsic, background: nil),
        scale: CGFloat = UIScreen.main.scale,
        fonts: FontConfig = .empty
    ) throws -> UIImage {
        let rendered: RenderedImage
        if fonts.isConfigured {
            rendered = try renderWithFontConfig(svg: data, options: options, fonts: fonts)
        } else {
            rendered = try render(svg: data, options: options)
        }
        return try rendered.uiImage(scale: scale)
    }

    public static func measure(data: Data) throws -> CGSize {
        let size = try intrinsicSize(svg: data)
        return CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
    }

    public static func contentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func fontCacheSignature(_ fonts: FontConfig) -> String {
        fonts.cacheSignature
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

public extension FontConfig {
    static let empty = FontConfig(dirs: [], data: [], aliases: [], defaultFamily: nil)

    var isConfigured: Bool {
        !dirs.isEmpty || !data.isEmpty || !aliases.isEmpty || defaultFamily != nil
    }

    /// Content-stable key for bitmap caches. Uses count + `Data.hashValue` so
    /// gallery tiles do not SHA-256 every font blob on each layout.
    var cacheSignature: String {
        let dataSig = data.map { "\($0.count):\($0.hashValue)" }.joined(separator: ",")
        let aliasSig = aliases.map { "\($0.requested)=\($0.replacement)" }.joined(separator: ",")
        return "\(dirs.joined(separator: ","))|\(dataSig)|\(aliasSig)|\(defaultFamily ?? "")"
    }
}
