import Foundation
import Combine

/// 收藏：本地缓存 +（登录后）云端 /radio/like 同步。与 Alger 的 favorite store 同构。
@MainActor
final class LikedStore: ObservableObject {
    static let shared = LikedStore()

    @Published private(set) var ids: Set<Int> = []
    @Published var syncError: String?
    private var synced = false

    private init() {
        let saved = UserDefaults.standard.array(forKey: "ncm.likedIds") as? [Int] ?? []
        ids = Set(saved)
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids).sorted(by: >), forKey: "ncm.likedIds")
    }

    func contains(_ id: Int) -> Bool { ids.contains(id) }

    /// 登录后首次拉取云端喜欢列表并与本地合并（对应 Alger getLikedList + reverse + 合并）
    func syncFromServerIfNeeded() async {
        guard Account.shared.isLoggedIn, !synced, let uid = Account.shared.userId else { return }
        do {
            let server = try await NCMClient.shared.likedIds(uid: uid)
            ids.formUnion(server)
            synced = true
            persist()
        } catch {
            syncError = "云端收藏拉取失败：\(error.localizedDescription)"
        }
    }

    func resetSync() { synced = false }

    func toggle(_ song: Song) async {
        let willLike = !ids.contains(song.id)
        if willLike { ids.insert(song.id) } else { ids.remove(song.id) }
        persist()
        // 只有真实登录才同步到云端（Alger 同款限制）
        guard Account.shared.isLoggedIn else { return }
        do {
            try await NCMClient.shared.like(songId: song.id, like: willLike)
        } catch {
            if willLike { ids.remove(song.id) } else { ids.insert(song.id) }
            persist()
            syncError = "收藏同步失败：\(error.localizedDescription)"
        }
    }
}
