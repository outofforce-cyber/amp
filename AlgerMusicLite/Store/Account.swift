import Foundation
import Combine

/// 登录账号状态：核心是 MUSIC_U cookie（与 Alger 存 localStorage('token') 等价）
@MainActor
final class Account: ObservableObject {
    static let shared = Account()

    @Published var profile: AccountResp.Profile?
    @Published var musicU: String? {
        didSet {
            UserDefaults.standard.set(musicU, forKey: "ncm.musicU")
        }
    }

    var isLoggedIn: Bool { profile != nil && musicU != nil }
    var userId: Int? { profile?.userId }

    private init() {
        musicU = UserDefaults.standard.string(forKey: "ncm.musicU")
        if let data = UserDefaults.standard.data(forKey: "ncm.profile"),
           let p = try? JSONDecoder().decode(AccountResp.Profile.self, from: data) {
            profile = p
        }
    }

    func login(musicU: String) async throws {
        self.musicU = musicU
        let resp: AccountResp = try await NCMClient.shared.account()
        guard let p = resp.profile else {
            self.musicU = nil
            throw NCMError.api(code: -1, message: "登录失败：无法获取账号信息")
        }
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "ncm.profile")
        }
    }

    func logout() {
        musicU = nil
        profile = nil
        UserDefaults.standard.removeObject(forKey: "ncm.profile")
    }
}

struct NCMError: Error, LocalizedError {
    let code: Int
    let message: String?
    static func api(code: Int, message: String) -> NCMError { NCMError(code: code, message: message) }
    var errorDescription: String? { message ?? "请求失败(\(code))" }
}
