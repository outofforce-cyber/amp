import Foundation
import CommonCrypto
import Security

/// NetEase Music API request encryption (ported from netease-cloud-music-api-alger).
/// weapi is no longer usable against music.163.com (empty body), so only eapi is used.
enum NCMCrypto {
    static let eapiKey = "e82ckenh8dichen8"
    static let separator = "-36cd479b6b5-"

    static func hexToData(_ h: String) -> Data {
        var d = Data()
        var i = h.startIndex
        while i < h.endIndex {
            d.append(UInt8(h[i...h.index(after: i)], radix: 16) ?? 0)
            i = h.index(i, offsetBy: 2)
        }
        return d
    }

    static func md5Hex(_ d: Data) -> String {
        var out = Data(count: Int(CC_MD5_DIGEST_LENGTH))
        out.withUnsafeMutableBytes { o in
            d.withUnsafeBytes { i in CC_MD5(i.baseAddress, CC_LONG(d.count), o) }
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    static func aesECBEncrypt(_ data: Data, key: String) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var outLen = 0
        let st = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { i in
                key.withCString { k in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                            k, key.utf8.count, nil, i.baseAddress, data.count,
                            o.baseAddress, o.count, &outLen)
                }
            }
        }
        guard st == kCCSuccess else { return nil }
        return out.prefix(outLen)
    }

    /// eapi: AES-ECB hex-uppercase of "uri-36cd479b6b5-text-36cd479b6b5-md5(nobodyuriusetextmd5forencrypt)"
    static func eapiParams(uri: String, payload: [String: Any]) -> String? {
        guard let jdata = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: jdata, encoding: .utf8) else { return nil }
        let message = "nobody\(uri)use\(text)md5forencrypt"
        let digest = md5Hex(Data(message.utf8))
        let line = "\(uri)\(separator)\(text)\(separator)\(digest)"
        guard let enc = aesECBEncrypt(Data(line.utf8), key: eapiKey) else { return nil }
        return enc.map { String(format: "%02X", $0) }.joined()
    }
}
