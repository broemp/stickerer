import SwiftUI

@main
struct StickererApp: App {
    @State private var incoming: String?

    var body: some Scene {
        WindowGroup {
            ContentView(incoming: $incoming)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "stickerer",
                          let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "url" })?.value
                    else { return }
                    incoming = link
                }
        }
    }
}
