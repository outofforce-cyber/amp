import SwiftUI

struct SongRow: View {
    let song: Song
    let rank: Int?
    var onPlay: () -> Void
    @ObservedObject private var liked = LikedStore.shared
    @ObservedObject private var account = Account.shared
    @ObservedObject private var downloads = DownloadStore.shared
    @ObservedObject private var quality = QualityStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if let rank {
                Text("\(rank)")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Color.red : .secondary)
                    .frame(width: 24)
            }
            CoverImage(url: song.coverURL, size: "120y120")
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                HStack(spacing: 6) {
                    Text(song.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if song.fee == 1 {
                        Text("VIP").font(.caption2).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                            .foregroundStyle(.red)
                    }
                    if let q = quality.text(for: song.id) {
                        Text(q).font(.caption2).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                    if !song.playableHeuristic {
                        Text("不可播").font(.caption2).lineLimit(1).fixedSize().foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 6)
            if downloads.contains(song.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.green)
                    .accessibilityLabel("已下载，可离线播放")
            }
            Button {
                LyricPresenter.shared.open(song)
            } label: {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
            }
            if song.hasMV {
                Button {
                    MVPresenter.shared.open(id: song.mv!, title: song.title)
                } label: {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await liked.toggle(song) }
            } label: {
                Image(systemName: liked.contains(song.id) ? "heart.fill" : "heart")
                    .foregroundStyle(liked.contains(song.id) ? Color.red : .secondary)
            }
            Text(song.durationText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .opacity(song.playableHeuristic ? 1 : 0.5)
        .contextMenu {
            Button {
                Task { await DownloadStore.shared.download(song) }
            } label: {
                Label {
                    Text("下载")
                } icon: {
                    Image(systemName: DownloadStore.shared.contains(song.id) ? "checkmark.circle" : "arrow.down.circle")
                }
            }
            .disabled(DownloadStore.shared.contains(song.id))
            Button {
                LyricPresenter.shared.open(song)
            } label: {
                Label("查看歌词", systemImage: "text.bubble")
            }
        }
    }
}
