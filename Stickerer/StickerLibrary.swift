import UIKit

/// Persists every sticker the app has made so old ones can be re-used.
/// Each sticker is two files in Application Support/Library: `<uuid>.webp` and a `<uuid>.png` thumbnail.
/// The directory listing (ordered by modification date) is the index.
@MainActor
final class StickerLibrary: ObservableObject {
    @Published private(set) var stickers: [Sticker] = []

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() { if !ScreenshotMode.isActive { load() } }

    func save(_ new: [Sticker]) {
        for s in new where !stickers.contains(where: { $0.id == s.id }) {
            let base = dir.appendingPathComponent(s.id.uuidString)
            do {
                try s.webp.write(to: base.appendingPathExtension("webp"), options: .atomic)
                try s.firstFrame.pngData()?.write(to: base.appendingPathExtension("png"), options: .atomic)
            } catch { continue }
            stickers.insert(s, at: 0)
        }
    }

    #if DEBUG
    /// Screenshot mode: show demo stickers without touching the saved library.
    func setDemo(_ demo: [Sticker]) { stickers = demo }
    #endif

    func delete(_ s: Sticker) {
        let base = dir.appendingPathComponent(s.id.uuidString)
        try? FileManager.default.removeItem(at: base.appendingPathExtension("webp"))
        try? FileManager.default.removeItem(at: base.appendingPathExtension("png"))
        stickers.removeAll { $0.id == s.id }
    }

    private func load() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        let dated: [(Sticker, Date)] = files.filter { $0.pathExtension == "webp" }.compactMap { url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let webp = try? Data(contentsOf: url),
                  let png = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("png")),
                  let img = UIImage(data: png) else { return nil }
            let date = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return (Sticker(id: id, webp: webp, firstFrame: img), date)
        }
        stickers = dated.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
