import Foundation

/// 直连网易云 API（eapi 加密），对应 Alger 本地 API 服务的能力，全部内嵌在 App 内。
final class NCMClient {
    static let shared = NCMClient()

    private let apiDomain = "https://interface.music.163.com/eapi/"
    private let ua = "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)"

    private lazy var deviceId: String = {
        if let v = UserDefaults.standard.string(forKey: "ncm.deviceId") { return v }
        let v = (0..<32).map { _ in String("0123456789abcdef".randomElement()!) }.joined()
        UserDefaults.standard.set(v, forKey: "ncm.deviceId")
        return v
    }()

    private init() {}

    // MARK: - eapi core

    private func eapiHeader() -> [String: String] {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var h: [String: String] = [
            "osver": "Microsoft-Windows-10-Professional-build-19045-64bit",
            "deviceId": deviceId,
            "os": "pc",
            "appver": "3.1.17.204416",
            "versioncode": "140",
            "mobilename": "",
            "buildver": String(String(nowMs).prefix(10)),
            "resolution": "1920x1080",
            "__csrf": "",
            "channel": "netease",
            "requestId": "\(nowMs)_\(String(format: "%04d", Int.random(in: 0..<1000)))",
        ]
        if let musicU = UserDefaults.standard.string(forKey: "ncm.musicU") {
            h["MUSIC_U"] = musicU
        }
        return h
    }

    /// 返回 (body, responseHeaders)；headers 用于读取登录接口的 Set-Cookie
    func callRaw(uri: String, _ payload: [String: Any] = [:]) async throws -> (Data, [AnyHashable: Any]) {
        var data = payload
        let header = eapiHeader()
        data["header"] = header
        data["e_r"] = false                       // 响应保持明文
        guard let params = NCMCrypto.eapiParams(uri: uri, payload: data) else {
            throw NCMError.api(code: -1, message: "加密失败")
        }
        let path = String(uri.dropFirst(5))       // 去掉 "/api/"
        guard let url = URL(string: apiDomain + path) else {
            throw NCMError.api(code: -1, message: "URL 无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(header.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
                     forHTTPHeaderField: "Cookie")
        req.httpBody = Data("params=\(params)".utf8)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        if (http?.statusCode ?? 0) >= 400 {
            throw NCMError.api(code: http?.statusCode ?? -1, message: "HTTP 错误")
        }
        if respData.isEmpty {
            throw NCMError.api(code: -1, message: "服务器返回为空，可能被风控")
        }
        return (respData, http?.allHeaderFields ?? [:])
    }

    func call<T: Decodable>(uri: String, _ payload: [String: Any] = [:], as type: T.Type) async throws -> T {
        let (data, _) = try await callRaw(uri: uri, payload)
        guard let obj = try? JSONDecoder().decode(T.self, from: data) else {
            throw NCMError.api(code: -1, message: "数据解析失败")
        }
        if let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? Int,
           code >= 400 {
            throw NCMError.api(code: code, message: "接口返回错误")
        }
        return obj
    }

    // MARK: - endpoints（与调研得到的 eapi 路径一致）

    /// 所有榜单
    func toplist() async throws -> [ToplistItem] {
        let r: ToplistResp = try await call(uri: "/api/toplist", as: ToplistResp.self)
        return r.list ?? []
    }

    /// 榜单/歌单详情（注意：参数必须是字符串，服务端才返回曲目）
    func playlistDetail(id: Int, limit: Int = 500) async throws -> PlaylistResp.Detail? {
        let r: PlaylistResp = try await call(uri: "/api/v6/playlist/detail",
                                             ["id": String(id), "n": String(limit), "s": "0"],
                                             as: PlaylistResp.self)
        return r.playlist
    }

    /// 搜索：1 单曲 / 1004 MV（每页 30，与 Alger 一致）
    func search(keyword: String, type: Int = 1, offset: Int = 0) async throws -> SearchResp {
        try await call(uri: "/api/cloudsearch/pc",
                       ["s": keyword, "type": type, "limit": 30, "offset": offset],
                       as: SearchResp.self)
    }

    /// 批量歌曲详情（用 trackIds 补齐信息）
    func songDetail(ids: [Int]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        var out: [Song] = []
        for chunk in stride(from: 0, to: ids.count, by: 300).map({ Array(ids[$0..<min($0+300, ids.count)]) }) {
            let c = chunk.map { "{\"id\":\($0)}" }.joined(separator: ",")
            let r: SongDetailResp = try await call(uri: "/api/v3/song/detail", ["c": "[" + c + "]"],
                                                   as: SongDetailResp.self)
            out.append(contentsOf: r.songs ?? [])
        }
        return out
    }

    /// 播放地址；url 为空或带 freeTrialInfo 视为不可播（Alger 同款判断）
    struct PlayableURL { let url: URL; let expiresAt: Date?; let bitrate: Int?; let format: String }
    func songURL(id: Int, level: String = "higher") async throws -> PlayableURL? {
        let r: SongURLResp = try await call(uri: "/api/song/enhance/player/url/v1",
                                            ["ids": "[\(id)]", "level": level, "encodeType": "flac"],
                                            as: SongURLResp.self)
        guard let item = r.data?.first, let s = item.url, !s.isEmpty, item.freeTrialInfo == nil,
              let url = URL(string: s) else { return nil }
        let exp = item.expi.map { Date(timeIntervalSince1970: TimeInterval($0 / 1000)) }
        let fmt = (item.type?.lowercased() == "flac") ? "flac" : "mp3"
        return PlayableURL(url: url, expiresAt: exp, bitrate: item.br, format: fmt)
    }

    /// 批量取播放地址与码率（列表音质徽标用）。返回 id -> bps（不可播的没有条目）
    func playableBitrates(ids: [Int], level: String = "exhigh") async -> [Int: Int] {
        var out: [Int: Int] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            let idList = "[" + chunk.map(String.init).joined(separator: ",") + "]"
            let r: SongURLResp? = try? await call(uri: "/api/song/enhance/player/url/v1",
                                                  ["ids": idList, "level": level, "encodeType": "flac"],
                                                  as: SongURLResp.self)
            for item in r?.data ?? [] {
                if let id = item.id, let br = item.br, item.url != nil { out[id] = br }
            }
        }
        return out
    }

    func lyric(id: Int) async throws -> LyricResp {
        try await call(uri: "/api/song/lyric/v1",
                       ["id": id, "cp": false, "tv": 0, "lv": 0, "rv": 0, "kv": 0, "yv": 0, "ytv": 0, "yrv": 0],
                       as: LyricResp.self)
    }

    /// MV 播放地址（1080P MP4，与 Alger 相同）
    func mvURL(id: Int) async throws -> URL? {
        let r: MVURLResp = try await call(uri: "/api/song/enhance/play/mv/url", ["id": id, "r": 1080],
                                          as: MVURLResp.self)
        guard let s = r.data?.url, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    // MARK: - 登录（QR）

    func qrKey() async throws -> String {
        let r: QRKeyResp = try await call(uri: "/api/login/qrcode/unikey", ["type": 3], as: QRKeyResp.self)
        guard let k = r.unikey else { throw NCMError.api(code: -1, message: "获取二维码失败") }
        return k
    }

    private func extractCookie(_ headers: [AnyHashable: Any], name: String) -> String? {
        let setCookies = headers["Set-Cookie"] as? String
            ?? (headers["set-cookie"] as? [String])?.joined(separator: ", ")
            ?? ""
        for part in setCookies.components(separatedBy: ", ") {
            if let m = part.range(of: name + "=") {
                let v = part[m.upperBound...].components(separatedBy: ";").first ?? ""
                if !v.isEmpty { return String(v) }
            }
        }
        return nil
    }

    /// 801 等待扫码 / 802 已扫码待确认 / 803 成功 / 800 过期
    func qrCheck(key: String) async throws -> (Int, String?) {
        let (data, headers) = try await callRaw(uri: "/api/login/qrcode/client/login", ["key": key, "type": 3])
        let resp = try? JSONDecoder().decode(QRCheckResp.self, from: data)
        let code = resp?.code ?? -1
        let musicU = extractCookie(headers, name: "MUSIC_U")
        return (code, musicU)
    }

    func account() async throws -> AccountResp {
        try await call(uri: "/api/nuser/account/get", as: AccountResp.self)
    }

    // MARK: - 收藏

    /// 红心收藏/取消（需要登录）
    func like(songId: Int, like: Bool) async throws {
        struct OK: Codable {}
        _ = try await call(uri: "/api/radio/like",
                           ["alg": "itembased", "trackId": songId, "like": like, "time": "3"],
                           as: OK.self)
    }

    /// 喜欢列表 id（需要登录）
    func likedIds(uid: Int) async throws -> [Int] {
        let r: LikedIdsResp = try await call(uri: "/api/song/like/get", ["uid": uid], as: LikedIdsResp.self)
        return r.ids ?? []
    }

    /// 每日推荐（需要登录）
    func dailySongs() async throws -> [Song] {
        let r: DailySongsResp = try await call(uri: "/api/v1/recommend/songs", as: DailySongsResp.self)
        return r.dailySongs ?? []
    }
}
