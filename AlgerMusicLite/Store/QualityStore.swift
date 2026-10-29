import Foundation
import Combine

/// 列表音质徽标：列表接口匿名态不带音质，播放地址接口可批量给出真实可播码率，
/// 列表加载后异步补全（与下载页记录的真实 br 同一套标注格式）。
@MainActor
final class QualityStore: ObservableObject {
    static let shared = QualityStore()

    @Published private(set) var map: [Int: Int] = [:]   // id -> bps

    private init() {}

    func text(for id: Int) -> String? {
        guard let br = map[id] else {
            // 已下载的歌可直接用下载记录的真实音质
            if let rec = DownloadStore.shared.record(for: id) { return rec.qualityText }
            return nil
        }
        if br >= 900_000 { return "HI-RES" }
        if br >= 290_000 { return "320k" }
        if br >= 180_000 { return "192k" }
        if br >= 120_000 { return "128k" }
        return "\(max(32, br / 1000))k"
    }

    func prime(_ songs: [Song]) {
        let missing = songs.map(\.id).filter { map[$0] == nil }
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let fetched = await NCMClient.shared.playableBitrates(ids: missing)
            await MainActor.run {
                fetched.forEach { self.map[$0.key] = $0.value }
            }
        }
    }
}
