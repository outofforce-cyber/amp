import SwiftUI

struct RootView: View {
    @StateObject private var account = Account.shared
    @StateObject private var liked = LikedStore.shared
    @StateObject private var player = PlayerManager.shared
    @StateObject private var mv = MVPresenter.shared
    @StateObject private var lyric = LyricPresenter.shared
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var playlists = PlaylistStore.shared

    var body: some View {
        ZStack {
            TabView {
                HomeView()
                    .tabItem { Label("热歌", systemImage: "chart.bar") }
                SearchView()
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                FavoriteView()
                    .tabItem { Label("收藏", systemImage: "heart") }
                DownloadsView()
                    .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            }
            if mv.target != nil {
                MVOverlay()
            }
            if lyric.song != nil {
                LyricOverlay()
            }
            if let notice = player.notice ?? downloads.message ?? playlists.toast {
                Text(notice)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        await MainActor.run { clearNotice() }
                    }
            }
        }
        .sheet(isPresented: $player.showSheet) {
            PlayerSheet()
                .presentationDetents([.large])
                .interactiveDismissDisabled(player.current == nil)
        }
        .animation(.default, value: player.current?.id)
        .animation(.default, value: mv.target?.id)
        // 调试入口：simctl launch 加 -debugAutoPlay YES 自动播放；-debugMV YES 打开 MV 验证横屏
        .task {
            if UserDefaults.standard.bool(forKey: "debugAutoPlay") {
                let s = try? await NCMClient.shared.songDetail(ids: [347230])
                if let s, let first = s.first {
                    player.playQueue(s, at: 0)
                }
            }
            if UserDefaults.standard.bool(forKey: "debugMV") {
                MVPresenter.shared.open(id: 10901520, title: "调试 MV")
            }
        }
    }

    private func clearNotice() { player.notice = nil; downloads.message = nil; playlists.toast = nil }
}
