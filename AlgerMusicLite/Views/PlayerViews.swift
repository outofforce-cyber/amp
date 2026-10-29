import SwiftUI

/// 迷你播放条（挂在各页面的 safeAreaInset 上，不会遮挡标签栏；可关闭）
struct MiniPlayerBar: View {
    @ObservedObject var player = PlayerManager.shared

    var body: some View {
        if let song = player.current {
            HStack(spacing: 12) {
                Button { player.showSheet = true } label: {
                    HStack(spacing: 10) {
                        CoverImage(url: song.coverURL, size: "120y120")
                            .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.body).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(song.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if !player.queueSource.isEmpty {
                                    Text("· \(player.queueSource)")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.tail)
                                }
                            }
                        }
                        Spacer(minLength: 6)
                    }
                }
                .buttonStyle(.plain)
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderless)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderless)
                Button { player.stop() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    let total = max(player.duration, 0.01)
                    Rectangle().fill(Color.accentColor.opacity(0.7))
                        .frame(width: geo.size.width * min(player.currentTime / total, 1), height: 2.5)
                }
            }
            .transition(.move(edge: .bottom))
        }
    }
}

/// 全屏播放页：封面/进度/控制/收藏/MV/歌词
struct PlayerSheet: View {
    @ObservedObject var player = PlayerManager.shared
    @ObservedObject var liked = LikedStore.shared
    @ObservedObject var downloads = DownloadStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: [LyricLine] = []
    @State private var lyricCurrent = 0
    @State private var scrubTarget: Double?      // 拖动进度条期间的目标位置

    var body: some View {
        if let song = player.current {
            NavigationStack {
                VStack(spacing: 14) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        Spacer()
                        Text(player.queueSource.isEmpty
                             ? "正在播放"
                             : "正在播放 · \(player.queueSource)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if song.hasMV {
                            Button { MVPresenter.shared.open(id: song.mv!, title: song.title) } label: {
                                Image(systemName: "film")
                            }
                        }
                    }
                    CoverImage(url: song.coverURL, size: "500y500")
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                    VStack(spacing: 2) {
                        Text(song.title).font(.headline).lineLimit(1)
                        Text(song.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    progressBar(song)
                    controls
                    lyricView
                }
                .padding()
                .toolbar(.hidden)
                .task(id: song.id) {
                    lyrics = []
                    let r = try? await NCMClient.shared.lyric(id: song.id)
                    lyrics = LRCParser.parse(r?.lrc?.lyric ?? r?.yrc?.lyric)
                }
            }
        }
    }

    private func progressBar(_ song: Song) -> some View {
        let dur = player.duration > 0 ? player.duration : Double(song.dt ?? 0) / 1000
        // 拖动中显示手指位置（不被定时刷新拉回），松手才 seek
        let sliderValue = Binding<Double>(
            get: { scrubTarget ?? player.currentTime },
            set: { scrubTarget = $0 }
        )
        return VStack(spacing: 2) {
            Slider(
                value: sliderValue,
                in: 0...max(dur, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        scrubTarget = player.currentTime
                    } else if let t = scrubTarget {
                        player.seek(t)
                        scrubTarget = nil
                    }
                }
            )
            HStack {
                Text(timeStr(scrubTarget ?? player.currentTime)).font(.caption).monospacedDigit()
                Spacer()
                Text(timeStr(dur)).font(.caption).monospacedDigit()
            }
        }
    }

    private var modeIcon: String {
        switch player.playMode {
        case .sequential: return "list.number"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        case .listLoop: return "repeat"
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { player.cyclePlayMode() } label: {
                Image(systemName: modeIcon)
                    .font(.title2)
                    .foregroundStyle(player.playMode == .sequential ? Color.primary : Color.accentColor)
            }
            Button {
                Task { await DownloadStore.shared.download(player.current!) }
            } label: {
                Image(systemName: downloads.contains(player.current!.id) ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(downloads.contains(player.current!.id) ? Color.green : .primary)
            }
            .disabled(downloads.pending.contains(player.current!.id))
            .overlay {
                if downloads.pending.contains(player.current!.id) {
                    ProgressView().controlSize(.small)
                }
            }
            Button { liked.toggleLikeButton(player.current!) } label: {
                Image(systemName: liked.contains(player.current!.id) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(liked.contains(player.current!.id) ? .red : .primary)
            }
            Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title2) }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.title2) }
        }
    }

    private var lyricView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lyrics.enumerated()), id: \.element.id) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.subheadline)
                            .foregroundStyle(i == lyricCurrent ? Color.primary : Color.secondary)
                            .id(i)
                            .onTapGesture { player.seek(line.time) }
                    }
                    if lyrics.isEmpty {
                        Text("暂无歌词").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.top, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: player.currentTime) { t in
                let idx = lyrics.lastIndex { $0.time <= t } ?? -1
                if idx >= 0 && idx != lyricCurrent {
                    lyricCurrent = idx
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }

    private func timeStr(_ t: Double) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension LikedStore {
    func toggleLikeButton(_ song: Song) { Task { await toggle(song) } }
}
