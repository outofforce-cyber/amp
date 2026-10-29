import Foundation

struct Artist: Codable, Hashable {
    let id: Int?
    let name: String?
}

struct Album: Codable, Hashable {
    let id: Int?
    let name: String?
    let picUrl: String?
}

struct Privilege: Codable, Hashable {
    let st: Int?      // < 0 表示下架/屏蔽
    let fee: Int?     // 0 免费 / 1 付费VIP / 4 数字专辑
    let pl: Int?      // 可播放码率 kbps
    let dl: Int?      // 可下载码率
    let paid: Int?
    let flag: Int?
    let freeTrialPrivilege: FreeTrialPrivilege?
    struct FreeTrialPrivilege: Codable, Hashable {
        let resConsumable: Bool?
        let userConsumable: Bool?
    }
}

struct Song: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let ar: [Artist]?
    let al: Album?
    let dt: Int?          // 时长（毫秒）
    let fee: Int?
    let st: Int?
    let mv: Int?
    let tns: [String]?
    let privilege: Privilege?

    var artistName: String {
        (ar ?? []).compactMap { $0.name }.joined(separator: " / ")
    }
    var title: String {
        guard let name, !name.isEmpty else { return "未知歌曲" }
        let alias = (tns ?? []).first
        return alias.map { "\(name) (\($0))" } ?? name
    }
    var coverURL: String? { al?.picUrl }
    var durationText: String {
        guard let dt else { return "" }
        let s = dt / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    var hasMV: Bool { (mv ?? 0) > 0 }
    /// 展示用的粗略可播判断（真实可播以运行时取 URL 为准，与 Alger 一致）
    var playableHeuristic: Bool {
        if (privilege?.st ?? st ?? 0) < 0 { return false }
        return true
    }
}

struct ToplistItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let coverImgUrl: String?
    let playCount: Int?
    let updateFrequency: String?
}
struct ToplistResp: Codable { let list: [ToplistItem]? }

struct PlaylistResp: Codable {
    struct Detail: Codable {
        let id: Int
        let name: String?
        let coverImgUrl: String?
        let description: String?
        let tracks: [Song]?
    }
    let playlist: Detail?
}

struct MVItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let artistName: String?
    let ar: [Artist]?
    let artists: [Artist]?
    let cover: String?
    let coverUrl: String?
    let picUrl: String?
    let duration: Int?
    let playTime: Int?
    var title: String { name ?? "MV \(id)" }
    var artistDisplay: String {
        artistName ?? (ar ?? artists ?? []).compactMap { $0.name }.joined(separator: " / ")
    }
    var coverURL: String? { cover ?? coverUrl ?? picUrl }
    var durationText: String {
        let ms = duration ?? playTime ?? 0
        let s = ms / 1000
        return s > 0 ? String(format: "%d:%02d", s / 60, s % 60) : ""
    }
}

struct SearchResp: Codable {
    struct Result: Codable {
        let songs: [Song]?
        let mvs: [MVItem]?
    }
    let result: Result?
}

struct SongURLResp: Codable {
    struct FreeTrialInfo: Codable {
        let startCount: Int?
        let endCount: Int?
        let rule: [String: String]?
    }
    struct Item: Codable {
        let id: Int?
        let url: String?
        let br: Int?
        let size: Int?
        let type: String?
        let expi: Int?
        let freeTrialInfo: FreeTrialInfo?
    }
    let data: [Item]?
}

struct LyricResp: Codable {
    struct L: Codable { let lyric: String? }
    let lrc: L?
    let yrc: L?
    let tlyric: L?
}

struct MVURLResp: Codable {
    struct D: Codable { let url: String?; let r: Int?; let expi: Int? }
    let data: D?
}

struct QRKeyResp: Codable { let unikey: String? }

struct QRCheckResp: Codable { let code: Int?; let message: String? }

struct AccountResp: Codable {
    struct Profile: Codable, Hashable {
        let userId: Int?
        let nickname: String?
        let avatarUrl: String?
        let vipType: Int?
    }
    let profile: Profile?
}

struct LikedIdsResp: Codable { let ids: [Int]? }

struct DailySongsResp: Codable { let dailySongs: [Song]? }

struct SongDetailResp: Codable { let songs: [Song]? }
