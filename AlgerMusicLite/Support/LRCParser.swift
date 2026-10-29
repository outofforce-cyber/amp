import Foundation

struct LyricLine: Identifiable, Hashable {
    let id = Int.random(in: 0..<Int.max)
    let time: Double      // 秒
    let text: String
}

/// 网易 /song/lyric/v1 的 lyric 字段是混合格式：
/// - 若干 JSON 行（署名/元信息或逐字 yrc）：{"t":1000,"c":[{"tx":"作词: "},{"tx":"…"}]}，逐字行含 "l":"[startMs,off]"
/// - 正文是标准 LRC 行：[00:18.466]text（一行可含多个时间标签）
/// 因此逐行识别两种格式并合并。
enum LRCParser {
    static func parse(_ raw: String?) -> [LyricLine] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var lines: [LyricLine] = []
        for s in raw.components(separatedBy: .newlines) {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("{") {
                parseJSONLine(t, into: &lines)
            } else {
                parseLRCLine(t, into: &lines)
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    // MARK: JSON line (credit meta or yrc word line)

    private static func parseJSONLine(_ s: String, into lines: inout [LyricLine]) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return }
        let baseSec = Double((obj["t"] as? Int) ?? 0) / 1000
        let c = obj["c"] as? [[String: Any]] ?? []
        var text = ""
        var startMs: Double?
        for e in c {
            if let tx = e["tx"] as? String {
                text += tx
            } else if let cw = e["cw"] as? [[String: Any]] {
                text += cw.compactMap { $0["w"] as? String }.joined()
            }
            if let l = e["l"] as? String, startMs == nil {
                let nums = l.components(separatedBy: CharacterSet(charactersIn: "[] ,"))
                    .compactMap { Double($0) }
                startMs = nums.first
            }
        }
        guard !text.isEmpty else { return }
        lines.append(LyricLine(time: (startMs ?? baseSec * 1000) / 1000, text: text))
    }

    // MARK: classic LRC line

    private static let tag = try! NSRegularExpression(
        pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
    )

    private static func parseLRCLine(_ s: String, into lines: inout [LyricLine]) {
        let range = NSRange(s.startIndex..., in: s)
        let matches = tag.matches(in: s, range: range)
        guard let last = matches.last else { return }
        guard let upper = Range(last.range, in: s).map({ $0.upperBound }) else { return }
        let text = String(s[upper...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        for m in matches {
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: s) else { return nil }
                return String(s[r])
            }
            let min = Double(group(1) ?? "0") ?? 0
            let sec = Double(group(2) ?? "0") ?? 0
            let fracStr = group(3)
            let frac = (Double(fracStr ?? "0") ?? 0) / pow(10, Double(fracStr?.count ?? 1))
            lines.append(LyricLine(time: min * 60 + sec + frac, text: text))
        }
    }
}
