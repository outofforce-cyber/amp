import SwiftUI

/// 扫码登录：unikey -> 轮询（801/802/803/800，同 Alger QrLogin.vue）。
/// 关键语义：新码取到后保持**模糊**，直到轮询得到服务端“等待扫码/已扫码”状态
/// （证明这张码真正激活可用）才清晰显示；完整链接每个 key 只生成一次，避免图案跳变。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var account = Account.shared
    @State private var qrKey: String?
    @State private var qrFull: String?            // 每个 key 只生成一次的完整链接（含固定 chainId）
    @State private var qrReady = false            // 服务端确认激活后才清晰
    @State private var status = "正在获取登录二维码…"
    @State private var failed = false
    @State private var pollTask: Task<Void, Never>?

    private let qrURLPrefix = "https://music.163.com/st/platform/scanlogin?codekey="

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ZStack {
                    QRCodeView(content: qrFull ?? (qrURLPrefix + "loading-placeholder"))
                        .frame(width: 220, height: 220)
                        .blur(radius: qrReady ? 0 : 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial.opacity(qrReady ? 0 : 0.55))
                        )
                        .animation(.easeInOut(duration: 0.45), value: qrReady)
                    if !qrReady {
                        VStack(spacing: 8) {
                            if !failed { ProgressView() }
                            Text(status).font(.caption).foregroundStyle(failed ? .red : .secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(width: 220, height: 220)

                if qrReady, let qrFull {
                    ShareLink(item: Image(uiImage: QRCodeView.qrImage(qrFull)),
                              preview: SharePreview("登录二维码",
                                                   image: Image(uiImage: QRCodeView.qrImage(qrFull)))) {
                        Label("分享到微信（长按识别登录）", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }

                if qrReady {
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                }
                Button(failed ? "重新获取二维码" : "刷新二维码") { restart() }
                Spacer()
            }
            .padding()
            .navigationTitle("登录网易云账号")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { stop(); dismiss() }
                }
            }
            .onAppear { restart() }
            .onDisappear { stop() }
        }
    }

    // MARK: - 流程

    /// 完整链接：key + 一次性生成的 chainId（同一 key 期间绝不重新生成）
    private func buildFullURL(key: String) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let rnd = String((0..<31).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        return qrURLPrefix + key + "&chainId=v1_\(rnd)_web_login_\(ts)&hdw_device=web&hdw_appid=web"
    }

    private func restart() {
        stop()
        qrReady = false
        qrFull = nil
        failed = false
        status = "正在获取登录二维码…"
        Task {
            do {
                let k = try await NCMClient.shared.qrKey()
                qrKey = k
                qrFull = buildFullURL(key: k)     // 生成一次，固定不变
                status = "正在等待服务端激活这张码…"
                startPolling(k)
            } catch {
                failed = true
                status = "获取二维码失败：\(error.localizedDescription)"
            }
        }
    }

    private func startPolling(_ key: String) {
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                do {
                    let (code, musicU) = try await NCMClient.shared.qrCheck(key: key)
                    switch code {
                    case 801:
                        // 服务端确认码已激活：此刻才清晰显示
                        qrReady = true
                        status = "等待扫码"
                    case 802:
                        qrReady = true
                        status = "已扫码，请在手机上确认"
                    case 803:
                        status = "登录成功"
                        if let musicU {
                            try? await account.login(musicU: musicU)
                        }
                        if account.isLoggedIn {
                            LikedStore.shared.resetSync()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            dismiss()
                        } else {
                            markExpired()
                        }
                        return
                    default:
                        markExpired()
                        return
                    }
                } catch {
                    // 网络抖动继续轮询
                }
            }
        }
    }

    private func markExpired() {
        failed = true
        qrReady = false
        status = "二维码已失效，请点击重新获取"
    }

    private func stop() { pollTask?.cancel(); pollTask = nil }
}
