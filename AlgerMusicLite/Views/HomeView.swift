import SwiftUI

/// 首页：榜单（trending）。默认热歌榜；登录后增加"每日推荐"。
/// 与 Alger 一致：榜单来自 /toplist，曲目来自 /v6/playlist/detail。
struct HomeView: View {
    @StateObject private var account = Account.shared
    @State private var charts: [ToplistItem] = []
    @State private var selectedChartID: Int?
    @State private var dailyMode = false
    @State private var songs: [Song] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showLogin = false

    private let hotListID = 3778678   // 热歌榜（网易固定 id，Alger 从 /toplist 取同样的列表）

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if account.isLoggedIn {
                            chip(title: "每日推荐", on: dailyMode) {
                                dailyMode = true; loadDaily()
                            }
                        }
                        ForEach(charts.prefix(20)) { c in
                            chip(title: c.name ?? "榜单", on: !dailyMode && selectedChartID == c.id) {
                                dailyMode = false
                                selectedChartID = c.id
                                loadChart(c.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                List {
                    if let errorText {
                        Text(errorText).foregroundStyle(.secondary)
                    }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                        SongRow(song: s, rank: dailyMode ? nil : i + 1) {
                            PlayerManager.shared.playQueue(songs, at: i, from: currentSourceName)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if loading { ProgressView() }
                }
            }
            .navigationTitle(dailyMode ? "每日推荐" : (charts.first(where: { $0.id == selectedChartID })?.name ?? "热歌榜"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if account.isLoggedIn {
                            Label(account.profile?.nickname ?? "已登录",
                                  systemImage: "person.crop.circle.badge.checkmark")
                                .font(.subheadline)
                            if let uid = account.userId {
                                Text("网易云 UID: \(uid)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if (account.profile?.vipType ?? 0) > 0 {
                                Label("VIP 会员", systemImage: "crown.fill")
                                    .foregroundStyle(.orange)
                            }
                            Divider()
                            Button("退出登录", role: .destructive) {
                                account.logout()
                                LikedStore.shared.resetSync()
                            }
                        } else {
                            Button("登录（扫码/微信识别）") { showLogin = true }
                        }
                    } label: {
                        if account.isLoggedIn {
                            HStack(spacing: 5) {
                                Text(shortName)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: 130, alignment: .trailing)
                                CoverImage(url: account.profile?.avatarUrl, size: "100y100")
                                    .frame(width: 20, height: 20).clipShape(Circle())
                            }
                        } else {
                            Label("登录", systemImage: "person.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogin) { LoginView() }
            .task {
                if charts.isEmpty { await loadCharts() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        }
    }

    private var shortName: String {
        let n = (account.profile?.nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "已登录" : String(n.prefix(8))
    }

    private var currentSourceName: String {
        if dailyMode { return "每日推荐" }
        return charts.first(where: { $0.id == selectedChartID })?.name ?? "热歌榜"
    }

    private func chip(title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12)))
                .foregroundStyle(on ? Color.accentColor : .primary)
        }
    }

    private func loadCharts() async {
        loading = true
        do {
            charts = try await NCMClient.shared.toplist()
            if selectedChartID == nil {
                selectedChartID = charts.first(where: { $0.id == hotListID })?.id ?? charts.first?.id
                loadChart(selectedChartID!)
            } else { loading = false }
        } catch {
            errorText = "榜单加载失败：\(error.localizedDescription)"
            loading = false
        }
    }

    private func loadChart(_ id: Int) {
        loading = true; errorText = nil
        Task {
            do {
                if let detail = try await NCMClient.shared.playlistDetail(id: id) {
                    songs = detail.tracks ?? []
                    QualityStore.shared.prime(songs)
                } else {
                    errorText = "该歌单无曲目"
                }
            } catch {
                errorText = "加载失败：\(error.localizedDescription)"
            }
            loading = false
        }
    }

    private func loadDaily() {
        loading = true; errorText = nil
        Task {
            do {
                songs = try await NCMClient.shared.dailySongs()
                QualityStore.shared.prime(songs)
                if songs.isEmpty { errorText = "暂无每日推荐（账号无权限或未开通）" }
            } catch {
                errorText = "每日推荐需要登录，且可能受账号限制：\(error.localizedDescription)"
            }
            loading = false
        }
    }
}
