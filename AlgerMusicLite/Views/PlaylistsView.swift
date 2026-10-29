import SwiftUI

/// 我的歌单列表（嵌在收藏页的“歌单”分段里）
struct PlaylistsListView: View {
    @ObservedObject private var store = PlaylistStore.shared
    @State private var renameTarget: UserPlaylist?
    @State private var renameText = ""

    var body: some View {
        Group {
            if store.playlists.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list").font(.system(size: 56)).foregroundStyle(.secondary)
                    Text("长按任意歌曲 → 添加到歌单\n歌单支持顺序 / 随机 / 单曲循环播放")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.playlists) { p in
                        NavigationLink(value: Route.playlist(p.id)) {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.title2).foregroundStyle(.red)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).lineLimit(1)
                                    Text("\(p.songs.count) 首").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.delete(p.id) } label: { Text("删除") }
                        }
                        .contextMenu {
                            Button {
                                renameTarget = p; renameText = p.name
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button(role: .destructive) {
                                store.delete(p.id)
                            } label: { Label("删除歌单", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    _ = store.create()
                } label: { Image(systemName: "plus") }
            }
        }
        .alert("重命名歌单", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("歌单名称", text: $renameText)
            Button("保存") {
                if let t = renameTarget { store.rename(t.id, to: renameText) }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        }
    }
}

enum Route: Hashable { case playlist(UUID) }

/// 歌单详情：播放全部 / 随机播放 / 移除歌曲 / 重命名 / 删除
struct PlaylistDetailView: View {
    let id: UUID
    @ObservedObject private var store = PlaylistStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var renameText = ""

    private var playlist: UserPlaylist? { store.playlists.first { $0.id == id } }

    var body: some View {
        Group {
            if let pl = playlist {
                List {
                    ForEach(Array(pl.songs.enumerated()), id: \.element.id) { i, s in
                        SongRow(song: s, rank: nil) {
                            PlayerManager.shared.playQueue(pl.songs, at: i, from: "歌单「\(pl.name)」")
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.remove(songId: s.id, from: id)
                            } label: { Text("移出歌单") }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle(pl.name)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            PlayerManager.shared.playQueue(pl.songs, at: 0, from: "歌单「\(pl.name)」")
                        } label: { Image(systemName: "play.circle") }
                        .disabled(pl.songs.isEmpty)
                        Button {
                            PlayerManager.shared.playQueue(pl.songs, at: Int.random(in: 0..<pl.songs.count), from: "歌单「\(pl.name)」")
                        } label: { Image(systemName: "shuffle.circle") }
                        .disabled(pl.songs.isEmpty)
                        Menu {
                            Button {
                                renameText = pl.name; showRename = true
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button(role: .destructive) {
                                store.delete(id); dismiss()
                            } label: { Label("删除歌单", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .alert("重命名歌单", isPresented: $showRename) {
                    TextField("歌单名称", text: $renameText)
                    Button("保存") { store.rename(id, to: renameText); showRename = false }
                    Button("取消", role: .cancel) { showRename = false }
                }
            } else {
                Text("歌单不存在或已删除").foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}
