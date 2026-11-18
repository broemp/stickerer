import SwiftUI
import ImageIO

private enum Theme {
    static let bg = Color(red: 0.055, green: 0.078, blue: 0.067)      // #0e1411
    static let panel = Color(red: 0.090, green: 0.125, blue: 0.106)   // #17201b
    static let line = Color(red: 0.149, green: 0.204, blue: 0.173)    // #26342c
    static let text = Color(red: 0.933, green: 0.961, blue: 0.941)    // #eef5f0
    static let muted = Color(red: 0.561, green: 0.639, blue: 0.596)   // #8fa398
    static let green = Color(red: 0.145, green: 0.827, blue: 0.400)   // #25d366
    static let greenDark = Color(red: 0.090, green: 0.502, blue: 0.247)
    static let ink = Color(red: 0.020, green: 0.133, blue: 0.059)     // #05220f
    static let pink = Color(red: 1, green: 0.373, blue: 0.635)        // #ff5fa2
}

struct ContentView: View {
    @Binding var incoming: String?
    @State private var link = ""
    @State private var cover = false
    @State private var split = false
    @State private var status = ""
    @State private var error = ""
    @State private var stickers: [Sticker] = []
    @StateObject private var library = StickerLibrary()

    private var busy: Bool { !status.isEmpty }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.green.opacity(0.2), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.pink.opacity(0.13), .clear], center: .leading, startRadius: 0, endRadius: 320)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    linkRow
                    HStack {
                        fitPicker
                        Spacer()
                    }
                    Toggle("Split into 3 clips", isOn: $split)
                        .tint(Theme.green)
                        .foregroundStyle(Theme.muted)
                        .font(.system(size: 14, design: .rounded))

                    if busy {
                        VStack(spacing: 10) {
                            CatLoader().frame(width: 120, height: 120)
                            Text(status).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                    if !error.isEmpty {
                        Text(error).foregroundStyle(Color(red: 1, green: 0.48, blue: 0.48))
                    }
                    if !stickers.isEmpty { pack }
                    if !library.stickers.isEmpty { libraryGrid }

                    Link("Source on GitHub", destination: URL(string: "https://github.com/broemp/stickerer")!)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.text)
        .screenshotMode(link: $link, status: $status, error: $error, stickers: $stickers,
                        cover: $cover, split: $split, library: library)
        .onChange(of: incoming) { value in
            guard let value else { return }
            incoming = nil
            guard !busy else { return }
            link = value
            Task { await make() }
        }
        .onAppear {
            // cold launch from the share extension: the binding is already set
            if let value = incoming, !busy {
                incoming = nil
                link = value
                Task { await make() }
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🏷️")
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Theme.green, radius: 0, y: 6)
                .rotationEffect(.degrees(-8))
                .padding(.bottom, 12)
            HStack(spacing: 8) {
                Text("Tweet").foregroundStyle(Theme.text)
                Text("→").foregroundStyle(Theme.green)
                Text("sticker")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .background(Theme.pink, in: RoundedRectangle(cornerRadius: 9))
                    .rotationEffect(.degrees(-2))
            }
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.7).lineLimit(1)
            Text("Paste a tweet or a direct video/GIF link, or share a tweet to this app. Get WhatsApp stickers.")
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 12)
    }

    private var linkRow: some View {
        VStack(spacing: 10) {
            TextField("", text: $link, prompt: Text("https://x.com/user/status/123…").foregroundColor(Theme.muted))
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)   // no .autocorrectionDisabled(): it hides the QuickType bar and its Paste suggestion
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit { if !busy && !link.isEmpty { Task { await make() } } }
                .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
                .overlay(alignment: .trailing) {
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { link = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.green)
                    .padding(.trailing, 8)
                }
                .padding(.vertical, 6)
                .background(Theme.panel, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 2))
            Button { Task { await make() } } label: {
                Text(busy ? status : "Make sticker").lineLimit(1)
            }
            .buttonStyle(PillButton())
            .disabled(busy || link.isEmpty)
            .opacity(busy || link.isEmpty ? 0.6 : 1)
        }
    }

    private var fitPicker: some View {
        HStack(spacing: 4) {
            segment("Fit · padded", selected: !cover) { cover = false }
            segment("Fill · cropped", selected: cover) { cover = true }
        }
        .padding(4)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 2))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .regular, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(selected ? Theme.bg : Theme.muted)
                .background(selected ? Theme.text : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pack: some View {
        VStack(spacing: 16) {
            Text("Pack · \(stickers.count)/30 · needs at least 1")
                .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                ForEach(Array(stickers.enumerated()), id: \.element.id) { i, s in
                    VStack(spacing: 8) {
                        Image(uiImage: s.firstFrame)
                            .resizable().scaledToFit().frame(height: 100)
                            .stickerOutline()
                        Text(s.fits ? "\(s.webp.count / 1024) KB" : "\(s.webp.count / 1024) KB — over 500 KB")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(s.fits ? Theme.muted : Color(red: 1, green: 0.7, blue: 0.28))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 2))
                    .rotationEffect(.degrees(i % 2 == 0 ? -1.5 : 1.5))
                    .contextMenu {
                        Button("Remove", role: .destructive) { stickers.removeAll { $0.id == s.id } }
                    }
                }
            }
            Button("Add to WhatsApp") {
                if !WhatsAppExport.send(stickers: stickers, name: "Stickerer", publisher: "Stickerer") {
                    error = "Could not hand the pack to WhatsApp."
                }
            }
            .buttonStyle(PillButton())
            .disabled(stickers.count < 1 || stickers.count > 30 || !WhatsAppExport.canSend)
            .opacity(stickers.count < 1 || stickers.count > 30 || !WhatsAppExport.canSend ? 0.6 : 1)
        }
        .padding(.top, 12)
    }

    private var libraryGrid: some View {
        VStack(spacing: 12) {
            Text("Library · \(library.stickers.count) · tap to add to pack")
                .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                ForEach(library.stickers) { s in
                    let inPack = stickers.contains { $0.id == s.id }
                    Button {
                        if !inPack && stickers.count < 30 { stickers.append(s) }
                    } label: {
                        Image(uiImage: s.firstFrame)
                            .resizable().scaledToFit().frame(height: 64)
                            .stickerOutline()
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(inPack ? Theme.green : Theme.line, lineWidth: 2))
                            .opacity(inPack ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete from library", role: .destructive) {
                            stickers.removeAll { $0.id == s.id }
                            library.delete(s)
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: work

    private func make() async {
        error = ""
        defer { status = "" }
        do {
            status = "Looking up link…"
            let info = try await TweetResolver.resolve(link)
            for media in info.media {
                status = "Downloading video…"
                let file = try await Converter.download(media.url)
                defer { try? FileManager.default.removeItem(at: file) }
                let made = try await Converter.convert(videoFile: file, cover: cover, parts: split ? 3 : 1) { status = $0 }
                library.save(made)
                stickers.append(contentsOf: made)
            }
            link = ""   // done: clear the input
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: styling helpers

private struct PillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                // shadow lives on the shape only, so the label text stays crisp
                Capsule()
                    .fill(Theme.green)
                    .shadow(color: Theme.greenDark, radius: 0, y: configuration.isPressed ? 0 : 3)
            }
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension View {
    /// die-cut white sticker border
    func stickerOutline() -> some View {
        self.shadow(color: .white, radius: 0, x: 2, y: 0)
            .shadow(color: .white, radius: 0, x: -2, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: 2)
            .shadow(color: .white, radius: 0, x: 0, y: -2)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 8)
    }
}

/// Plays the same spinning-cat GIF as the website.
private struct CatLoader: UIViewRepresentable {
    static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "spinning-cat", withExtension: "gif"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<CGImageSourceGetCount(src) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        }
        return UIImage.animatedImage(with: frames, duration: max(total, 0.1))
    }()

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView(image: Self.image)
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {}
}
