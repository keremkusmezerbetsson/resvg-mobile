import CryptoKit
import Foundation
import ResvgMobile
import XCTest

/// Cross-platform SVG suite harness (512×512 Contain, transparent bg).
/// Writes `path\tsha256\twidth\theight` lines for compare-suite-results.py.
///
/// Fixtures layout mirrors the vendor tree so `../../../resources/...` hrefs
/// resolve when `resourcesDir` is the SVG parent directory.
final class SuiteRenderTests: XCTestCase {
    func testRenderSuiteAndWriteResults() throws {
        let fixtures = try XCTUnwrap(
            Bundle.module.resourceURL?.appendingPathComponent("Fixtures"),
            "Fixtures resource missing — run ./scripts/sync-suite-assets.sh"
        )
        let manifestURL = fixtures.appendingPathComponent("manifest.txt")
        let manifestName = (try? String(contentsOf: manifestURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "smoke"

        let paths = try listSuitePaths(fixtures: fixtures, manifest: manifestName)
        XCTAssertFalse(paths.isEmpty, "expected suite fixtures under Fixtures/suite")

        let dumpMismatch = ProcessInfo.processInfo.environment["DUMP_MISMATCH"] == "1"
            || ProcessInfo.processInfo.environment["SIMCTL_CHILD_DUMP_MISMATCH"] == "1"
        let outPath = ProcessInfo.processInfo.environment["SUITE_RESULTS_PATH"]
            ?? ProcessInfo.processInfo.environment["SIMCTL_CHILD_SUITE_RESULTS_PATH"]
            ?? "/tmp/ios-results.jsonl"
        let dumpRoot = (ProcessInfo.processInfo.environment["SUITE_DUMP_DIR"]
            ?? ProcessInfo.processInfo.environment["SIMCTL_CHILD_SUITE_DUMP_DIR"])
            .map { URL(fileURLWithPath: $0) }

        let options = RenderOptions(
            width: 512,
            height: 512,
            fit: .contain,
            background: Rgba(r: 0, g: 0, b: 0, a: 0)
        )

        let fonts: FontConfig
        if manifestName == "full" {
            let fontFolder = fixtures.appendingPathComponent("suite-fonts")
            fonts = loadFonts(from: fontFolder)
        } else {
            fonts = .empty
        }

        var lines: [String] = []
        var failures = 0
        for rel in paths {
            let url = fixtures.appendingPathComponent("suite").appendingPathComponent(rel)
            do {
                let svg = try Data(contentsOf: url)
                let resourcesDir = url.deletingLastPathComponent().path
                let img = try renderWithResources(
                    svg: svg,
                    options: options,
                    fonts: fonts,
                    resourcesDir: resourcesDir
                )
                let sha = sha256Hex(img.rgba)
                lines.append("\(rel)\t\(sha)\t\(img.width)\t\(img.height)")
                if dumpMismatch, let dumpRoot {
                    let rgbaURL = dumpRoot.appendingPathComponent("\(rel).rgba")
                    try FileManager.default.createDirectory(
                        at: rgbaURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try img.rgba.write(to: rgbaURL)
                    let meta = "\(img.width) \(img.height)\n"
                    try meta.write(
                        to: dumpRoot.appendingPathComponent("\(rel).meta"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            } catch {
                failures += 1
                fputs("FAIL \(rel): \(error)\n", stderr)
            }
        }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(toFile: outPath, atomically: true, encoding: .utf8)
        fputs("Wrote \(lines.count) results to \(outPath) (\(failures) failures)\n", stderr)
        let total = lines.count + failures
        let failRate = total == 0 ? 1.0 : Double(failures) / Double(total)
        // Smoke: zero tolerance. Full: match Rust ≤2% render-failure gate.
        let maxFailRate = manifestName == "full" ? 0.02 : 0.0
        XCTAssertLessThanOrEqual(
            failRate,
            maxFailRate,
            String(
                format: "suite had %d/%d render failures (rate=%.2f%%, max=%.0f%%)",
                failures,
                total,
                failRate * 100,
                maxFailRate * 100
            )
        )
    }

    private func listSuitePaths(fixtures: URL, manifest: String) throws -> [String] {
        switch manifest {
        case "smoke":
            let text = try String(
                contentsOf: fixtures.appendingPathComponent("smoke.txt"),
                encoding: .utf8
            )
            return text.split(whereSeparator: \.isNewline).compactMap { line in
                let parts = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let trimmed = parts[0].trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : String(trimmed)
            }
        case "full":
            let root = fixtures.appendingPathComponent("suite")
            return try walkSvgs(root: root, base: root)
        default:
            throw NSError(
                domain: "ResvgSuite",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "unknown manifest \(manifest)"]
            )
        }
    }

    private func walkSvgs(root: URL, base: URL) throws -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        let basePath = base.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(
            at: root.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return out }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "svg" else { continue }
            let urlPath = url.resolvingSymlinksInPath().path
            guard urlPath.hasPrefix(basePath + "/") else { continue }
            let rel = String(urlPath.dropFirst(basePath.count + 1))
            out.append(rel)
        }
        return out.sorted()
    }

    private func loadFonts(from folder: URL) -> FontConfig {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return .empty
        }
        let data: [Data] = files.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" || ext == "ttc" else { return nil }
            return try? Data(contentsOf: url)
        }
        return FontConfig(
            dirs: [],
            data: data,
            aliases: Resvg.defaultFontAliases,
            defaultFamily: "Noto Sans"
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
