import SwiftUI
import AVKit
import UIKit

/// 网易封面加载（与 Alger 相同：追加 ?param= 尺寸参数）
struct CoverImage: View {
    let url: String?
    var size: String = "200y200"
    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
            }
        }
    }
    private var imageURL: URL? {
        guard let url else { return nil }
        var s = url
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        s += (s.contains("?") ? "&" : "?") + "param=\(size)"
        return URL(string: s)
    }
}

@MainActor
final class MVPresenter: ObservableObject {
    static let shared = MVPresenter()
    @Published var target: (id: Int, title: String)?
    @Published var url: URL?
    @Published var loading = false
    @Published var errorText: String?

    private init() {}

    func open(id: Int, title: String) {
        target = (id, title)
        url = nil; errorText = nil; loading = true
        // 视频优先：暂停正在播放的音乐，并收起全屏播放页（否则 sheet 会盖住视频层）
        PlayerManager.shared.pause()
        PlayerManager.shared.showSheet = false
        Task { [weak self] in
            guard let self else { return }
            do {
                if let u = try await NCMClient.shared.mvURL(id: id) {
                    self.url = u
                } else {
                    self.errorText = "该 MV 无可用播放地址"
                }
            } catch {
                self.errorText = error.localizedDescription
            }
            self.loading = false
        }
    }
    func close() {
        target = nil; url = nil
    }
}

/// MV 全屏播放：黑底视频铺满，标题/关闭浮在画面上（无灰色工具条）
struct MVOverlay: View {
    @ObservedObject var presenter = MVPresenter.shared
    @State private var avPlayer = AVPlayer()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let url = presenter.url {
                VideoPlayer(player: avPlayer)
                    .ignoresSafeArea()
                    .onAppear { bind(url) }
                    .onChange(of: presenter.url) { newValue in bind(newValue) }
            }
            if presenter.loading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let e = presenter.errorText {
                Text(e).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let t = presenter.target {
                HStack(alignment: .top) {
                    Text(t.title)
                        .font(.headline).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .padding(12)
                    Spacer()
                    Button { presenter.close() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                    .padding(8)
                }
                .background(LinearGradient(colors: [.black.opacity(0.35), .clear],
                                           startPoint: .top, endPoint: .bottom))
            }
        }
        .onDisappear {
            avPlayer.pause()
            avPlayer.replaceCurrentItem(with: nil)
        }
        .transition(.opacity)
    }

    private func bind(_ url: URL?) {
        if let url {
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            avPlayer.play()
        } else {
            avPlayer.replaceCurrentItem(with: nil)
        }
    }
}

// MARK: - 歌词弹层

@MainActor
final class LyricPresenter: ObservableObject {
    static let shared = LyricPresenter()
    @Published var song: Song?
    @Published var lines: [LyricLine] = []
    @Published var loading = false
    @Published var errorText: String?

    private init() {}

    func open(_ s: Song) {
        song = s
        lines = []; errorText = nil; loading = true
        Task { [weak self] in
            guard let self else { return }
            let r = try? await NCMClient.shared.lyric(id: s.id)
            let parsed = LRCParser.parse(r?.lrc?.lyric ?? r?.yrc?.lyric)
            self.lines = parsed
            if parsed.isEmpty { self.errorText = "暂无歌词" }
            self.loading = false
        }
    }
    func close() { song = nil; lines = [] }
}

struct LyricOverlay: View {
    @ObservedObject var p = LyricPresenter.shared
    @ObservedObject var player = PlayerManager.shared
    @State private var currentIndex = -1

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.94).ignoresSafeArea()
            if let song = p.song {
                VStack(spacing: 8) {
                    HStack {
                        Button { p.close() } label: {
                            Image(systemName: "chevron.down").font(.title3).foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(spacing: 1) {
                            Text(song.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                            Text(song.artistName).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            PlayerManager.shared.playQueue([song], at: 0,
                                from: PlayerManager.shared.queueSource)
                        } label: {
                            Image(systemName: "play.circle").font(.title3).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                    if p.loading {
                        ProgressView().tint(.white).padding(.top, 40)
                    } else if let e = p.errorText {
                        Text(e).foregroundStyle(.white.opacity(0.6)).padding(.top, 40)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    ForEach(Array(p.lines.enumerated()), id: \.element.id) { i, line in
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.system(size: i == currentIndex ? 18 : 15,
                                                          weight: i == currentIndex ? .semibold : .regular))
                                            .foregroundStyle(i == currentIndex ? .white : .white.opacity(0.45))
                                            .id(i)
                                            .onTapGesture {
                                                PlayerManager.shared.playQueue([song], at: 0,
                                                    startOffset: line.time,
                                                    from: PlayerManager.shared.queueSource)
                                            }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 60)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onChange(of: player.currentTime) { t in
                                if player.current?.id != song.id { return }
                                let idx = p.lines.lastIndex { $0.time <= t } ?? -1
                                if idx >= 0 && idx != currentIndex {
                                    currentIndex = idx
                                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .transition(.move(edge: .bottom))
    }
}
