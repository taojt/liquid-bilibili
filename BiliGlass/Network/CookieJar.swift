import Foundation
import Security

/// 会话凭证管理。
///
/// B站登录态由四个 Cookie 组成：SESSDATA（凭证）、bili_jct（CSRF）、
/// DedeUserID（用户 ID）、DedeUserID__ckMd5（校验）。SESSDATA 等价于密码，
/// 明文落盘风险高，因此统一存 Keychain 而非 UserDefaults。
@MainActor
final class CookieJar {
    static let shared = CookieJar()

    private(set) var cookies: [String: String] = [:]

    private let service = "com.biliglass.session"
    private let account = "bili-cookies"

    /// 关注这几个键即可判断登录态
    private let trackedKeys = [
        "SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5", "buvid3", "buvid4"
    ]

    init() {
        load()
    }

    // MARK: - 查询

    var cookieHeader: String {
        cookies
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    var isLoggedIn: Bool {
        guard let sess = cookies["SESSDATA"], !sess.isEmpty else { return false }
        return cookies["DedeUserID"] != nil
    }

    var csrfToken: String { cookies["bili_jct"] ?? "" }
    var userID: String { cookies["DedeUserID"] ?? "" }

    // MARK: - 写入

    /// 从响应头吸收 Set-Cookie。
    /// 2026 年 8 月起 B站扫码登录改版，凭证只通过 Set-Cookie 下发，
    /// 不再拼在返回的 URL 上，所以必须解析响应头。
    func absorb(from response: HTTPURLResponse, url: URL) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
            if let k = pair.key as? String, let v = pair.value as? String {
                acc[k] = v
            }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        var changed = false
        for cookie in parsed where trackedKeys.contains(cookie.name) {
            cookies[cookie.name] = cookie.value
            changed = true
        }
        if changed { save() }
    }

    /// 手动写入（用于从 RefreshToken 等场景恢复）
    func set(_ name: String, _ value: String) {
        cookies[name] = value
        save()
    }

    func clear() {
        cookies.removeAll()
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cookies) else { return }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load() {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        cookies = decoded
    }
}
