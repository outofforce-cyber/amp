import Foundation
import Combine

struct UserPlaylist: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var songs: [Song]
}

/// 本地歌单（可多个）：创建/重命名/删除、添加与移除歌曲，JSON 持久化。
@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()

    @Published private(set) var playlists: [UserPlaylist] = []
    @Published var toast: String?

    private let storeKey = "ncm.playlists"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let ps = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlists = ps
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    @discardableResult
    func create(named name: String? = nil) -> UserPlaylist {
        let n = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "新建歌单 \(playlists.count + 1)"
        let p = UserPlaylist(id: UUID(), name: n, songs: [])
        playlists.insert(p, at: 0)
        persist()
        return p
    }

    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = n
        persist()
    }

    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
    }

    func add(_ song: Song, to id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        if playlists[i].songs.contains(where: { $0.id == song.id }) {
            toast = "《\(song.title)》已在「\(playlists[i].name)」中"
            return
        }
        playlists[i].songs.append(song)
        persist()
        toast = "已添加到「\(playlists[i].name)」"
    }

    func remove(songId: Int, from id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].songs.removeAll { $0.id == songId }
        persist()
    }

    func songs(in id: UUID) -> [Song] {
        playlists.first(where: { $0.id == id })?.songs ?? []
    }
}
