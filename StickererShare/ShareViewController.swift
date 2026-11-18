import UIKit
import UniformTypeIdentifiers

/// Share extension: grabs the shared tweet link and opens the main app via stickerer://make?url=…
/// Extensions can't officially open their host app, so we find UIApplication in the responder chain.
final class ShareViewController: UIViewController {
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.055, green: 0.078, blue: 0.067, alpha: 1)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(red: 0.145, green: 0.827, blue: 0.4, alpha: 1)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { @MainActor in await run() }
    }

    // MARK: flow

    @MainActor
    private func run() async {
        guard let link = await extractLink() else {
            return show("No link found in the shared item.")
        }
        var c = URLComponents(string: "stickerer://make")!
        c.queryItems = [URLQueryItem(name: "url", value: link)]
        guard let url = c.url else { return show("Could not build the app link.") }

        if openHostApp(url) {
            // give the system a moment to switch apps before tearing the extension down
            try? await Task.sleep(nanoseconds: 600_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            UIPasteboard.general.string = link
            show("Couldn't open Stickerer from here. The link was copied: open Stickerer and paste it.")
        }
    }

    private func extractLink() async -> String? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let v = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) {
                if let u = v as? URL { return u.absoluteString }
                if let s = v as? String { return s }
            }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let s = (try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier)) as? String,
               let hit = s.split(whereSeparator: \.isWhitespace).map(String.init).first(where: { $0.hasPrefix("http") }) {
                return hit
            }
        }
        // some apps put the link only in the item's text
        for item in items {
            if let s = item.attributedContentText?.string,
               let hit = s.split(whereSeparator: \.isWhitespace).map(String.init).first(where: { $0.hasPrefix("http") }) {
                return hit
            }
        }
        return nil
    }

    private func show(_ message: String) {
        let alert = UIAlertController(title: "Stickerer", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }

    // MARK: opening the host app

    /// Walks the responder chain to UIApplication and calls open(_:options:completionHandler:).
    /// The completion handler MUST be an Objective-C block, otherwise the call crashes.
    private func openHostApp(_ url: URL) -> Bool {
        typealias OpenFn = @convention(c) (AnyObject, Selector, URL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")

        var responder: UIResponder? = self
        while let r = responder {
            if r is UIApplication || String(describing: type(of: r)) == "UIApplication" {
                guard r.responds(to: selector) else { return false }
                let imp = r.method(for: selector)
                let open = unsafeBitCast(imp, to: OpenFn.self)
                open(r, selector, url, [:], nil)
                return true
            }
            responder = r.next
        }
        return false
    }
}
