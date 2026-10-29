import SwiftUI

/// 收藏页：分段 = 我喜欢（本地+云端喜欢列表） / 我的歌单（本地多歌单）。
struct FavoriteView: View {
    @StateObject private var account = Account.shared
    @StateObject private var liked = LikedStore.shared
    @State private var songs: [Song] = []
    @State private var loading = false
    @State private var showLogin = false
    @State private var section = 0        // 0 我喜欢 / 1 我的歌单
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    Text("我喜欢").tag(0)
                    Text("我的歌单").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if section == 0 { likedSection } else { PlaylistsListView() }
            }
            .navigationTitle("收藏")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .playlist(let id): PlaylistDetailView(id: id)
                }
            }
            .sheet(isPresented: $showLogin) { LoginView() }
            .task { if section == 0 { reload() } }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        }
    }

    private var likedSection: some View {
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
        .refreshable { reload() }
    }

    private func reload() {
        loading = true
        Task {
            await liked.syncFromServerIfNeeded()
            do {
                songs = try await NCMClient.shared.songDetail(ids: Array(liked.ids))
                QualityStore.shared.prime(songs)
            } catch {
                songs = []
            }
            loading = false
        }
    }
}
