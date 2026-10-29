import SwiftUI

/// 收藏页：本地+云端喜欢 id 列表 -> song/detail 批量取详情（与 Alger favorite 页同构）。
struct FavoriteView: View {
    @StateObject private var account = Account.shared
    @StateObject private var liked = LikedStore.shared
    @State private var songs: [Song] = []
    @State private var loading = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if !account.isLoggedIn && songs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.text.square").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("登录后收藏将同步到网易云「我喜欢」").font(.subheadline).foregroundStyle(.secondary)
                        Button("登录") { showLogin = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                        } header: {
                            HStack {
                                Text("我喜欢的音乐 · \(songs.count) 首")
                                Spacer()
                                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                                Button { showLogin = true } label: {
                                    Image(systemName: account.isLoggedIn ? "checkmark.circle" : "person.crop.circle")
                                }
                            }
                        }
                        ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                            SongRow(song: s, rank: nil) {
                                PlayerManager.shared.playQueue(songs, at: i)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        await liked.toggle(s)
                                        songs.remove(at: i)
                                    }
                                } label: { Text("移除收藏") }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay { if loading { ProgressView() } }
                }
            }
            .navigationTitle("收藏")
            .sheet(isPresented: $showLogin) { LoginView() }
            .task { reload() }
            .refreshable { reload() }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        }
    }

    private func reload() {
        loading = true
        Task {
            await liked.syncFromServerIfNeeded()
            do {
                songs = try await NCMClient.shared.songDetail(ids: Array(liked.ids))
                QualityStore.shared.prime(songs)
            } catch {
                // 本地列表兜底
                songs = []
            }
            loading = false
        }
    }
}
