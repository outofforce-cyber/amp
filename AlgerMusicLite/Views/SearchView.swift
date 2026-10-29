import SwiftUI

/// 搜索：单曲(type=1) / MV(type=1004)，30 条一页滚动加载，同 Alger SearchResult。
struct SearchView: View {
    @State private var keyword = ""
    @State private var type = 1
    @State private var songs: [Song] = []
    @State private var mvs: [MVItem] = []
    @State private var offset = 0
    @State private var loading = false
    @State private var searched = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索歌曲或 MV", text: $keyword)
                        .textFieldStyle(.plain)
                        .onSubmit { doSearch(reset: true) }
                    if !keyword.isEmpty {
                        Button { keyword = ""; clear() } label: { Image(systemName: "xmark.circle.fill") }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
                .padding(.horizontal)
                Picker("", selection: $type) {
                    Text("单曲").tag(1)
                    Text("MV").tag(1004)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                .padding(.vertical, 8)

                Group {
                    if type == 1 { songList } else { mvList }
                }
                .overlay { if loading && !searched { ProgressView() } }
            }
            .navigationTitle("搜索")
            .onChange(of: type) { _ in
                if searched { doSearch(reset: true) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        }
    }

    private var songList: some View {
        List {
            if let errorText { Text(errorText).foregroundStyle(.secondary) }
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                SongRow(song: s, rank: nil) {
                    PlayerManager.shared.playQueue(songs, at: i)
                }
            }
            if songs.count > offset { loadMoreButton }
        }
        .listStyle(.plain)
        .overlay { if searched && songs.isEmpty && errorText == nil { Text("没有找到相关歌曲").foregroundStyle(.secondary) } }
    }

    private var mvList: some View {
        List {
            if let errorText { Text(errorText).foregroundStyle(.secondary) }
            ForEach(mvs) { mv in
                HStack(spacing: 12) {
                    CoverImage(url: mv.coverURL, size: "300y300")
                        .frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mv.title).lineLimit(1)
                        Text(mv.artistDisplay).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(mv.durationText).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { MVPresenter.shared.open(id: mv.id, title: mv.title) }
            }
            if mvs.count > offset { loadMoreButton }
        }
        .listStyle(.plain)
        .overlay { if searched && mvs.isEmpty && errorText == nil { Text("没有找到相关 MV").foregroundStyle(.secondary) } }
    }

    private var loadMoreButton: some View {
        Button("加载更多") { doSearch(reset: false) }
            .frame(maxWidth: .infinity)
    }

    private func clear() {
        songs = []; mvs = []; offset = 0; searched = false; errorText = nil
    }

    private func doSearch(reset: Bool) {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        if reset { clear(); offset = 0 }
        loading = true; errorText = nil
        Task {
            do {
                let r = try await NCMClient.shared.search(keyword: kw, type: type, offset: offset)
                // 竞态守卫：返回时关键词已变则丢弃（Alger 同款）
                guard kw == keyword.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    loading = false; return
                }
                if type == 1 {
                    let newSongs = r.result?.songs ?? []
                    songs.append(contentsOf: newSongs)
                    QualityStore.shared.prime(newSongs)
                } else { mvs.append(contentsOf: r.result?.mvs ?? []) }
                offset += 30
                searched = true
            } catch {
                errorText = "搜索失败：\(error.localizedDescription)"
            }
            loading = false
        }
    }
}
