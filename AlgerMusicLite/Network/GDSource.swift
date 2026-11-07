import Foundation

/// GD音乐台 兜底源（移植 Alger 的多源解析链：netease → gdmusic → pyncmd）。
/// 官方 player/url 取不到地址时（典型场景：非 VIP 账号播 VIP 歌），尝试用
/// GD studio 的公开解析 API 换回直链：
///   1) pyncmd 路线：用同一个网易云 ID 直查 types=url&source=netease（最精确）
///   2) gdmusic 路线：按“歌名+歌手”在 joox/tidal/netease 搜索，核对歌名与
///      歌手后才换链——宁可失败也不返回错歌（Alger #704 的教训）
/// 服务可用性随时间波动，失败时退回原来的“暂时无法播放”提示。
enum GDSource {
    struct Media { let url: URL; let format: String; let bitrate: Int? }

    private static let base = "https://music-api.gdstudio.xyz/api.php"

    /// 统一入口：先按 ID 直查，再按名字搜索。br=999 最高（可能给 m3u8），320 更稳。
    static func resolve(song: Song, br: Int = 999) async -> Media? {
        if let m = await pyncmd(song.id, br: br) { return m }
        return await gdmusic(song, br: br)
    }

    // MARK: - 1) pyncmd：同 ID 直查官方直链

    private static func pyncmd(_ id: Int, br: Int) async -> Media? {
        guard let json = await get("types=url&source=netease&id=\(id)&br=\(br)") else { return nil }
        return media(from: json)
    }

    // MARK: - 2) gdmusic：搜索 + 严格核对后换链

    private static func gdmusic(_ song: Song, br: Int) async -> Media? {
        let songName = song.name ?? ""
        guard songName.count >= 2 else { return nil }
        let artists = (song.ar ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        let joined = ([songName] + artists).joined(separator: " ")
        let query = joined.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? joined

        for source in ["joox", "tidal", "netease"] {
            guard let data = await raw("types=search&source=\(source)&name=\(query)&count=5&pages=1"),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                  let pick = pickBest(candidates: arr, name: songName, artists: artists),
                  let trackId = jsonID(pick["id"]) else { continue }
            let realSource = (pick["source"] as? String) ?? source
            guard let json = await get("types=url&source=\(realSource)&id=\(trackId)&br=\(br)") else { continue }
            if let m = media(from: json) { return m }
        }
        return nil
    }

    /// 归一化：去括号备注（Live/翻唱/伴奏等）、空白标点，转小写。
    private static func normalize(_ text: String) -> String {
        var t = text.lowercased()
        while let r = t.range(of: "[(（【\\[][^)）\\]]*[)）\\]]", options: .regularExpression) {
            t.removeSubrange(r)
        }
        return t.replacingOccurrences(of: #"[^0-9a-z\u{4e00}-\u{9fff}\u{3040}-\u{30ff}\u{ac00}-\u{d7af}]+"#,
                                      with: "", options: .regularExpression)
    }

    private static func nameMatched(_ expected: String, _ candidate: String) -> Bool {
        let e = normalize(expected), c = normalize(candidate)
        guard !e.isEmpty, !c.isEmpty else { return false }
        return e == c || c.contains(e) || e.contains(c)
    }

    private static func artistText(_ artist: Any?) -> String {
        if let arr = artist as? [Any] {
            return arr.map { ($0 as? String) ?? (($0 as? [String: Any])?["name"] as? String) ?? "" }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        return (artist as? String) ?? ""
    }

    /// 挑选与原曲匹配的结果：歌名必须匹配；候选带歌手信息时歌手也必须匹配。
    private static func pickBest(candidates: [[String: Any]], name: String, artists: [String]) -> [String: Any]? {
        var best: [String: Any]?
        var bestScore = 0
        for item in candidates {
            guard jsonID(item["id"]) != nil,
                  nameMatched(name, (item["name"] as? String) ?? "") else { continue }
            let candArtist = normalize(artistText(item["artist"]))
            let score: Int
            if artists.isEmpty {
                score = 2
            } else if candArtist.isEmpty {
                score = 1
            } else {
                let hit = artists.contains { a in
                    let na = normalize(a)
                    return !na.isEmpty && (candArtist.contains(na) || na.contains(candArtist))
                }
                if !hit { continue }
                score = 3
            }
            if score > bestScore { bestScore = score; best = item }
        }
        return best
    }

    // MARK: - HTTP helpers

    private static func get(_ query: String) async -> [String: Any]? {
        guard let data = await raw(query),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    private static func raw(_ query: String) async -> Data? {
        guard let url = URL(string: "\(base)?\(query)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func jsonID(_ v: Any?) -> String? {
        if let i = v as? Int { return String(i) }
        if let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    private static func media(from json: [String: Any]) -> Media? {
        guard let s = json["url"] as? String, !s.isEmpty, let url = URL(string: s) else { return nil }
        let ext = url.pathExtension.lowercased()
        let format = ["mp3", "m4a", "flac", "wav", "m3u8"].contains(ext) ? ext : "mp3"
        let kbps = (json["br"] as? Int) ?? 0
        return Media(url: url, format: format, bitrate: kbps > 0 ? kbps * 1000 : nil)
    }
}
