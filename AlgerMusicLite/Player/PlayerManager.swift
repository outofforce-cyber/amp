import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// 播放能力：AVPlayer + 系统媒体控制（对应 Alger 的 Audio 元素 + MediaSession）。
/// 播放可用性判断与 Alger 相同：取 URL 时 url 为空或 freeTrialInfo 即失败。
@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    enum PlayMode: Int { case sequential = 0, shuffle = 1, repeatOne = 2, listLoop = 3 }
    var modeName: String {
        switch playMode {
        case .sequential: return "顺序播放"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单曲循环"
        case .listLoop: return "列表循环"
        }
    }

    @Published private(set) var current: Song?
    @Published private(set) var queueSource: String = ""   // 当前队列来源（榜单/歌单/收藏…）
    @Published private(set) var queue: [Song] = []
    @Published private(set) var index: Int = 0
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var notice: String?          // 不可播提示
    @Published var showSheet = false       // 全屏播放页
    @Published private(set) var playMode: PlayMode = .sequential

    let avPlayer = AVPlayer()
    private var timeToken: Any?
    private var endObserver: NSObjectProtocol?
    private var artworkCache: [Int: MPMediaItemArtwork] = [:]
    private var loadGen = 0
    private var pendingSeek: Double?

    private init() {
        playMode = PlayMode(rawValue: UserDefaults.standard.integer(forKey: "ncm.playMode")) ?? .sequential
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let rcc = MPRemoteCommandCenter.shared()
        rcc.playCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.resume() }
            return .success
        }
        rcc.pauseCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.pause() }
            return .success
        }
        rcc.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.next() }
            return .success
        }
        rcc.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerManager.shared.previous() }
            return .success
        }
        rcc.changePlaybackPositionCommand.addTarget { event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in PlayerManager.shared.seek(e.positionTime) }
            }
            return .success
        }
    }

    // MARK: - queue

    func playQueue(_ list: [Song], at start: Int, startOffset: Double? = nil, from source: String = "") {
        guard start < list.count else { return }
        queue = list
        index = start
        queueSource = source
        pendingSeek = startOffset
        loadCurrent(retries: 1)
    }

    func play(_ song: Song, from source: String = "") {
        playQueue([song], at: 0, from: source)
    }

    func toggle() { isPlaying ? pause() : resume() }

    func resume() {
        guard avPlayer.currentItem != nil else { loadCurrent(retries: 1); return }
        avPlayer.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        avPlayer.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func cyclePlayMode() {
        let nextMode = PlayMode(rawValue: (playMode.rawValue + 1) % 4) ?? .sequential
        playMode = nextMode
        UserDefaults.standard.set(nextMode.rawValue, forKey: "ncm.playMode")
        notice = "播放模式：\(modeName)"
    }

    private func randomOtherIndex() -> Int {
        var r = Int.random(in: 0..<queue.count)
        while r == index { r = Int.random(in: 0..<queue.count) }
        return r
    }

    func next() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .shuffle:
            if queue.count > 1 { index = randomOtherIndex() }
            loadCurrent(retries: 1)
        case .repeatOne:
            seek(0)
            avPlayer.play()
            isPlaying = true
        case .listLoop:
            index = (index + 1) % queue.count   // 到末尾回到第一首，无限循环
            loadCurrent(retries: 1)
        default:
            if index + 1 < queue.count {
                index += 1
                loadCurrent(retries: 1)
            } else {
                stop()          // 顺序播放到列表末尾：停止
            }
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        switch playMode {
        case .shuffle:
            if queue.count > 1 {
                index = randomOtherIndex()
                loadCurrent(retries: 1)
            } else {
                seek(0)
            }
        default:
            if index > 0 {
                index -= 1
                loadCurrent(retries: 1)
            } else {
                seek(0)
            }
        }
    }

    func seek(_ t: Double) {
        avPlayer.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        currentTime = t
        updateNowPlayingPosition()
    }

    func stop() {
        removeTimeObserver()
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        current = nil
        queue = []
        index = 0
        isPlaying = false
        currentTime = 0
        duration = 0
        showSheet = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - loading

    private func loadCurrent(retries: Int) {
        guard index < queue.count else { return }
        let song = queue[index]
        current = song
        loadGen += 1
        let gen = loadGen
        removeTimeObserver()
        currentTime = 0
        duration = 0

        Task { [weak self] in
            guard let self else { return }
            // 已下载的歌曲直接走本地文件（离线可播）
            if let local = DownloadStore.shared.localURL(for: song.id) {
                self.replaceItem(with: local, song: song)
                return
            }
            let result = try? await NCMClient.shared.songURL(id: song.id)
            guard gen == self.loadGen else { return }   // 期间又切了歌
            if let play = result {
                self.replaceItem(with: play.url, song: song)
            } else if retries > 0 {
                // 与 Alger 一致：先试 higher，失败再试 standard
                let lower = try? await NCMClient.shared.songURL(id: song.id, level: "standard")
                guard gen == self.loadGen else { return }
                if let play = lower {
                    self.replaceItem(with: play.url, song: song)
                } else {
                    self.giveUpOn(song)
                }
            } else {
                self.giveUpOn(song)
            }
        }
    }

    /// 取不到地址时：队列里还有别的歌则跳过；只有这一首则停止（避免单队列无限重试）
    private func giveUpOn(_ song: Song) {
        notice = "《\(song.title)》暂时无法播放"
        if queue.count > 1 {
            next()
        } else {
            stop()
            notice = "《\(song.title)》暂时无法播放"
        }
    }

    private func replaceItem(with url: URL, song: Song) {
        let item = AVPlayerItem(url: url)
        avPlayer.replaceCurrentItem(with: item)
        avPlayer.play()
        isPlaying = true
        addTimeObserver(for: item)
        watchItemEnd(item)
        if let t = pendingSeek {
            pendingSeek = nil
            seek(t)
        }
        updateNowPlaying()
    }

    /// 放完后的行为由播放模式决定（顺序到末尾会停止；随机切任意首；单曲循环重播）
    private func watchItemEnd(_ item: AVPlayerItem) {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.current != nil else { return }
                self.next()
            }
        }
    }

    private func addTimeObserver(for item: AVPlayerItem) {
        removeTimeObserver()
        timeToken = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                     queue: .main) { [weak self] t in
            let seconds = CMTimeGetSeconds(t)
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = seconds
                if let item = self.avPlayer.currentItem, item.duration.isNumeric {
                    self.duration = CMTimeGetSeconds(item.duration)
                }
                self.updateNowPlayingPosition()
            }
        }
    }
    private func removeTimeObserver() {
        if let t = timeToken { avPlayer.removeTimeObserver(t); timeToken = nil }
    }

    // MARK: - now playing（锁屏/控制中心）

    private func updateNowPlaying() {
        guard let song = current else { return }
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistName,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        info[MPMediaItemPropertyPlaybackDuration] = Double(song.dt ?? 0) / 1000
        if let cached = artworkCache[song.id] {
            info[MPMediaItemPropertyArtwork] = cached
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        if artworkCache[song.id] == nil { fetchArtwork(for: song) }
    }

    /// 锁屏/控制中心封面：下载专辑图并注入 nowPlayingInfo（按歌曲缓存）
    private func fetchArtwork(for song: Song) {
        guard var s = song.coverURL else { return }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        s += (s.contains("?") ? "&" : "?") + "param=500y500"
        guard let url = URL(string: s) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            await MainActor.run {
                guard let self else { return }
                self.artworkCache[song.id] = art
                if self.current?.id == song.id {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = art
                }
            }
        }
    }
    private func updateNowPlayingPosition() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
}
