import UIKit

/// Hands a sticker pack to WhatsApp exactly like WhatsApp's own sample (WhatsApp/stickers,
/// iOS/WAStickersThirdParty/Interoperability.swift + StickerPack.swift): JSON on the pasteboard
/// under a custom type, then open whatsapp://stickerPack.
enum WhatsAppExport {
    static let pasteboardType = "net.whatsapp.third-party.sticker-pack"

    static var canSend: Bool {
        if ScreenshotMode.isActive { return true }   // the simulator has no WhatsApp; keep the button looking enabled
        return UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!)
    }

    static func tray(from image: UIImage) -> Data? {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: fmt)
            .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 96, height: 96)) }
            .pngData()
    }

    @discardableResult
    static func send(stickers: [Sticker], name: String, publisher: String) -> Bool {
        guard stickers.count >= 1, stickers.count <= 30,
              let trayPNG = tray(from: stickers[0].firstFrame) else { return false }

        let json: [String: Any] = [
            "identifier": UUID().uuidString,
            "name": name,
            "publisher": publisher,
            "tray_image": trayPNG.base64EncodedString(),
            "animated_sticker_pack": true,
            "stickers": stickers.map {
                ["image_data": $0.webp.base64EncodedString(), "emojis": ["😀"], "accessibility_text": "Animated sticker"] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return false }

        UIPasteboard.general.setItems(
            [[pasteboardType: data]],
            options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: 60)]
        )
        DispatchQueue.main.async { UIApplication.shared.open(URL(string: "whatsapp://stickerPack")!) }
        return true
    }
}
