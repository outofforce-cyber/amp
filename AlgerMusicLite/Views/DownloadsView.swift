import SwiftUI

/// 下载管理：本地文件列表，可离线播放/删除
struct DownloadsView: View {
    @ObservedObject var store = DownloadStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("长按任意歌曲 → 下载，或直接在全屏播放页点下载按钮")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(Array(store.records.enumerated()), id: \.element.id) { i, rec in
                                row(rec, i)
                            }
                        } header: {
                            Text("本地歌曲 · \(store.records.count) 首")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("下载")
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        }
    }

    private func row(_ rec: DownloadRecord, _ i: Int) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: rec.song.coverURL, size: "120y120")
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.song.title).lineLimit(1)
                HStack(spacing: 6) {
                    Text(rec.song.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let q = rec.qualityText {
                        Text(q).font(.caption2).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                    Text(sizeText(rec.bytes)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                LyricPresenter.shared.open(rec.song)
            } label: {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
            }
            Button {
                PlayerManager.shared.playQueue(store.records.map { $0.song }, at: i, from: "本地下载")
            } label: {
                Image(systemName: "play.circle.fill").font(.title2)
            }
            Button(role: .destructive) {
                store.delete(rec)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            PlayerManager.shared.playQueue(store.records.map { $0.song }, at: i, from: "本地下载")
        }
    }

    private func sizeText(_ bytes: Int) -> String {
        if bytes > 1_000_000 { return String(format: "%.1fMB", Double(bytes) / 1_000_000) }
        return String(format: "%.0fKB", Double(bytes) / 1000)
    }
}
