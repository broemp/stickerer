import SwiftUI

#if DEBUG
/// Debug-only hook for `AppStoreScreenshots/make-screenshots.sh`. Launching with
/// `-screenshot "<step>; <step>; …"` fills the app with offline demo data (no network,
/// no WhatsApp needed) and plays the steps, so the script can grab the screen with
/// `simctl io screenshot` or record a video:
///
///     <scene>          show that scene: home, converting, pack, library, split
///     wait:<seconds>   pause (for the video tour)
///
/// The demo stickers come from the directory in `STICKERER_DEMO_DIR` (passed by the script as
/// `SIMCTL_CHILD_STICKERER_DEMO_DIR`): `NN.webp` + `NN.png` pairs from `make-demo-stickers.sh`.
enum ScreenshotMode {
    enum Scene: String { case home, converting, pack, library, split }
    enum Step { case show(Scene), wait(Double) }

    static let steps: [Step]? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-screenshot"), i + 1 < args.count else { return nil }
        return args[i + 1].split(separator: ";").compactMap { raw in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("wait:"), let s = Double(text.dropFirst(5).trimmingCharacters(in: .whitespaces)) { return .wait(s) }
            if let scene = Scene(rawValue: text) { return .show(scene) }
            if !text.isEmpty { print("ScreenshotMode: ignoring unknown step '\(text)'") }
            return nil
        }
    }()

    static var isActive: Bool { steps != nil }

    static let tweetURL = "https://x.com/catsdoingthings/status/1790000000000000000"

    static let demoStickers: [Sticker] = {
        guard let dir = ProcessInfo.processInfo.environment["STICKERER_DEMO_DIR"] else { return [] }
        return (1...12).compactMap { n in
            let name = String(format: "%02d", n)
            guard let webp = try? Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(name).webp")),
                  let png = UIImage(contentsOfFile: "\(dir)/\(name).png") else { return nil }
            return Sticker(webp: webp, firstFrame: png)
        }
    }()
}

private struct ScreenshotDriver: ViewModifier {
    @Binding var link: String
    @Binding var status: String
    @Binding var error: String
    @Binding var stickers: [Sticker]
    @Binding var cover: Bool
    @Binding var split: Bool
    @ObservedObject var library: StickerLibrary

    func body(content: Content) -> some View {
        content.task {
            guard let steps = ScreenshotMode.steps else { return }
            for step in steps {
                switch step {
                case .wait(let s): try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
                case .show(let scene): apply(scene)
                }
            }
        }
    }

    private func apply(_ scene: ScreenshotMode.Scene) {
        let demo = ScreenshotMode.demoStickers
        guard demo.count >= 12 else { error = "STICKERER_DEMO_DIR missing or incomplete."; return }
        error = ""; status = ""; link = ""; cover = false; split = false; stickers = []
        library.setDemo(Array(demo.reversed()))
        switch scene {
        case .home:
            link = ScreenshotMode.tweetURL
        case .converting:
            link = ScreenshotMode.tweetURL
            status = "Converting…"
        case .pack:
            stickers = Array(demo[0..<4])
        case .library:
            break   // empty pack: the whole library grid sits right under the controls
        case .split:
            split = true
            stickers = Array(demo[1..<4])
        }
    }
}

extension View {
    func screenshotMode(link: Binding<String>, status: Binding<String>, error: Binding<String>,
                        stickers: Binding<[Sticker]>, cover: Binding<Bool>, split: Binding<Bool>,
                        library: StickerLibrary) -> some View {
        modifier(ScreenshotDriver(link: link, status: status, error: error, stickers: stickers,
                                  cover: cover, split: split, library: library))
    }
}
#else
enum ScreenshotMode { static let isActive = false }

extension View {
    func screenshotMode(link: Binding<String>, status: Binding<String>, error: Binding<String>,
                        stickers: Binding<[Sticker]>, cover: Binding<Bool>, split: Binding<Bool>,
                        library: StickerLibrary) -> some View { self }
}
#endif
