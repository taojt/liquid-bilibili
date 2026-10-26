import Foundation
import CryptoKit

/// WBI 签名器。
///
/// B站从 2023 年起给 Web 接口加了 w_rid 签名：从 nav 接口拿到 img_key / sub_key，
/// 按固定 64 位置换表重排后取前 32 位得到 mixin_key，再把参数按 key 排序拼接、
/// 追加 mixin_key 做 MD5 得到 w_rid。缺少签名的 playurl 请求会返回 -403。
enum WBISigner {
    /// B站前端硬编码的置换表，不可改动
    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    /// 从 wbi_img 的两个 URL 里提取文件名，再置换出 mixin_key
    static func mixinKey(imgURL: String, subURL: String) -> String {
        let img = fileName(imgURL)
        let sub = fileName(subURL)
        let raw = Array(img + sub)
        var out = ""
        out.reserveCapacity(32)
        for i in mixinKeyEncTab.prefix(32) where i < raw.count {
            out.append(raw[i])
        }
        return out
    }

    /// https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png -> 7cd084941338484aae1ad9425b84077c
    private static func fileName(_ url: String) -> String {
        guard let last = url.split(separator: "/").last else { return "" }
        return String(last.split(separator: ".").first ?? last)
    }

    /// 对参数签名，返回带 wts / w_rid 的新参数字典
    static func sign(params: [String: String], mixinKey: String) -> [String: String] {
        var p = params
        p["wts"] = String(Int(Date().timeIntervalSince1970))

        let query = p.keys.sorted().map { key -> String in
            let raw = p[key] ?? ""
            // B站前端会剔除 !'()* 这几个字符，签名必须一致
            let cleaned = raw.filter { !"!'()*".contains($0) }
            return "\(key)=\(cleaned)"
        }.joined(separator: "&")

        p["w_rid"] = md5(query + mixinKey)
        return p
    }

    static func md5(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
