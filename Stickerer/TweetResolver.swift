import Foundation

struct TweetMedia {
    let url: URL
    let duration: Double?
}

struct TweetInfo {
    let author: String
    let media: [TweetMedia]
}

enum StickerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

/// Same lookup as the website: the CORS-free fxtwitter API.
enum TweetResolver {
    static func resolve(_ link: String) async throws -> TweetInfo {
        let pattern = #"(?:twitter|x|fxtwitter|vxtwitter|fixupx|fixvx)\.com/(?:[^/]+)/status(?:es)?/(\d+)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: link, range: NSRange(link.startIndex..., in: link)),
              let r = Range(m.range(at: 1), in: link)
        else {
            // Not a tweet: accept a direct link to a video or GIF file.
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: trimmed), let scheme = u.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", u.host != nil
            else { throw StickerError.message("Paste a tweet link or a direct link to a video or GIF.") }
            return TweetInfo(author: "", media: [TweetMedia(url: u, duration: nil)])
        }

        let (data, resp) = try await URLSession.shared.data(from: URL(string: "https://api.fxtwitter.com/status/\(link[r])")!)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw StickerError.message("Tweet lookup failed (\(h.statusCode)).")
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tweet = root?["tweet"] as? [String: Any]
        let all = (tweet?["media"] as? [String: Any])?["all"] as? [[String: Any]] ?? []
        let media: [TweetMedia] = all.compactMap {
            guard let t = $0["type"] as? String, t == "video" || t == "gif",
                  let s = $0["url"] as? String, let u = URL(string: s) else { return nil }
            return TweetMedia(url: u, duration: $0["duration"] as? Double)
        }
        guard !media.isEmpty else { throw StickerError.message("No video or GIF found in that tweet.") }
        let author = (tweet?["author"] as? [String: Any])?["screen_name"] as? String ?? ""
        return TweetInfo(author: author, media: media)
    }
}
