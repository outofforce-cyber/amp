import Foundation
import Combine

struct DownloadRecord: Codable, Identifiable {
    let song: Song
    let file: String      // Downloads 目录下的文件名
    let bytes: Int
    let br: Int?          // kbps*1000
    let date: Date
    var id: Int { song.id }

    /// 音质标注：FLAC 无损 / 320k / 192k / 128k…（按下载时记录的码率与格式）
    var qualityText: String? {
        if file.lowercased().hasSuffix(".flac") { return "FLAC" }
        guard let br else { return nil }
        if br >= 900_000 { return "HI-RES" }
        if br >= 290_000 { return "320k" }
        if br >= 180_000 { return "192k" }
        if br >= 120_000 { return "128k" }
        return "\(max(32, br / 1000))k"
    }
}

/// 音乐下载：取最高可用音质（exhigh→higher 降级，与 Alger 音质策略一致）存到本地文件。
/// 之后播放同 id 歌曲会直接走本地文件（PlayerManager 内置本地优先）。
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var pending = Set<Int>()     // 正在下载的歌曲 id
    @Published var message: String?

    private let dir: URL
    private let storeKey = "ncm.downloads"

    private init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let rs = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = rs.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func localURL(for id: Int) -> URL? {
        guard let r = records.first(where: { $0.song.id == id }) else { return nil }
        let u = dir.appendingPathComponent(r.file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func contains(_ id: Int) -> Bool { localURL(for: id) != nil }
    func record(for id: Int) -> DownloadRecord? { records.first { $0.song.id == id } }

    func download(_ song: Song) async {
        let id = song.id
        guard !pending.contains(id), !contains(id) else { return }
        pending.insert(id)
        defer { pending.remove(id) }
        // 先试无损/超品，失败降级标准（免费用户可播的最高档）
        var play = try? await NCMClient.shared.songURL(id: id, level: "exhigh")
        if play == nil { play = try? await NCMClient.shared.songURL(id: id, level: "higher") }
        guard let p = play else {
            message = "《\(song.title)》无免费下载源（可能需要 VIP/登录）"
            return
        }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: p.url)
            let fileName = "\(id).\(p.format)"
            let dst = dir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)
            let size = (try? dst.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let rec = DownloadRecord(song: song, file: fileName, bytes: size, br: p.bitrate, date: Date())
            records.insert(rec, at: 0)
            persist()
            message = "已下载《\(song.title)》"
        } catch {
            message = "下载失败：\(error.localizedDescription)"
        }
    }

    func delete(_ record: DownloadRecord) {
        let u = dir.appendingPathComponent(record.file)
        try? FileManager.default.removeItem(at: u)
        records.removeAll { $0.id == record.id }
        persist()
    }
}
