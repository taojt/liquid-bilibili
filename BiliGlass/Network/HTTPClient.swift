import Foundation

enum BiliError: LocalizedError {
    case badURL
    case http(Int)
    case api(code: Int, message: String)
    case decode(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址无效"
        case .http(let c): return "网络错误 HTTP \(c)"
        case .api(let code, let message):
            switch code {
            case -352: return "触发风控（-352），请稍后再试"
            case -403: return "无访问权限（-403）"
            case -404: return "内容不存在（-404）"
            case -10403: return "大会员专享内容"
            default: return "接口错误 \(code)：\(message)"
            }
        case .decode(let m): return "数据解析失败：\(m)"
        case .empty: return "空响应"
        }
    }
}

/// 判定「这次失败其实是任务被取消」。
///
/// SwiftUI 的 `.task` 在视图消失/重建时会取消，URLSession 随之抛 `URLError.cancelled`。
/// 这类取消不是真正的网络错误，直接展示给用户就会出现「无网络访问」的误报，
/// 因此各数据源都要先过这一层过滤。
extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        // URLError 统一桥接成 NSError 判断，避免对 existential 做类型转换
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

/// B站所有请求的统一出口。
///
/// 三个必须项：浏览器 UA、Referer、Cookie。缺 UA 或 Referer 会被 CDN 判定为抓取，
/// 直接 403；缺少 Cookie 则拿不到登录态画质。
final class HTTPClient {
    static let shared = HTTPClient()

    /// 用桌面 Safari 的 UA，B站对移动端 WebView UA 的风控更敏感
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    static let webReferer = "https://www.bilibili.com"

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        // 关闭系统自动 Cookie 管理，改由 CookieJar 显式注入，避免两套状态互相覆盖
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    // MARK: - 请求

    func getRaw(
        _ urlString: String,
        query: [String: String] = [:],
        referer: String? = nil,
        extraHeaders: [String: String] = [:],
        withCookies: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        guard var comps = URLComponents(string: urlString) else { throw BiliError.badURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw BiliError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(referer ?? Self.webReferer, forHTTPHeaderField: "Referer")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if withCookies {
            let header = await MainActor.run { CookieJar.shared.cookieHeader }
            if !header.isEmpty {
                req.setValue(header, forHTTPHeaderField: "Cookie")
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BiliError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw BiliError.http(http.statusCode)
        }
        // 吸收新的 Cookie（登录态刷新时会有新 Set-Cookie）
        await MainActor.run {
            CookieJar.shared.absorb(from: http, url: url)
        }
        return (data, http)
    }

    func get<T: Decodable>(
        _ urlString: String,
        query: [String: String] = [:],
        as type: T.Type,
        referer: String? = nil,
        withCookies: Bool = true
    ) async throws -> T {
        let (data, _) = try await getRaw(
            urlString,
            query: query,
            referer: referer,
            withCookies: withCookies
        )
        return try decode(data, as: type)
    }

    // MARK: - POST

    /// 互动类接口（点赞/投币/收藏）都是 POST 表单，
    /// 并且必须在表单里带 `csrf`（等于 Cookie 里的 bili_jct），少了直接 -111。
    func post<T: Decodable>(
        _ urlString: String,
        form: [String: String],
        as type: T.Type,
        referer: String? = nil
    ) async throws -> T {
        let wrapper = try await performPost(urlString, form: form, referer: referer, as: T.self)
        guard wrapper.code == 0 else {
            throw BiliError.api(code: wrapper.code, message: wrapper.message ?? "")
        }
        guard let payload = wrapper.data else { throw BiliError.empty }
        return payload
    }

    /// 有些写操作（进度上报）成功时 data 是 null，不能要求有 payload
    func postVoid(_ urlString: String, form: [String: String], referer: String? = nil) async throws {
        let wrapper = try await performPost(
            urlString, form: form, referer: referer, as: EmptyPayload.self
        )
        guard wrapper.code == 0 else {
            throw BiliError.api(code: wrapper.code, message: wrapper.message ?? "")
        }
    }

    private func performPost<T: Decodable>(
        _ urlString: String,
        form: [String: String],
        referer: String?,
        as type: T.Type
    ) async throws -> BiliResponse<T> {
        var params = form
        let csrf = await MainActor.run { CookieJar.shared.csrfToken }
        if !csrf.isEmpty {
            params["csrf"] = csrf
        }

        guard let url = URL(string: urlString) else { throw BiliError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(referer ?? Self.webReferer, forHTTPHeaderField: "Referer")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        req.httpBody = Self.formEncode(params).data(using: .utf8)

        let cookieHeader = await MainActor.run { CookieJar.shared.cookieHeader }
        if !cookieHeader.isEmpty {
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BiliError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw BiliError.http(http.statusCode)
        }
        await MainActor.run {
            CookieJar.shared.absorb(from: http, url: url)
        }
        do {
            return try JSONDecoder().decode(BiliResponse<T>.self, from: data)
        } catch {
            throw BiliError.decode(String(describing: error))
        }
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let wrapper: BiliResponse<T>
        do {
            wrapper = try JSONDecoder().decode(BiliResponse<T>.self, from: data)
        } catch {
            throw BiliError.decode(String(describing: error))
        }
        guard wrapper.code == 0 else {
            throw BiliError.api(code: wrapper.code, message: wrapper.message ?? "")
        }
        guard let payload = wrapper.data else { throw BiliError.empty }
        return payload
    }

    // MARK: - 表单编码

    private static func formEncode(_ params: [String: String]) -> String {
        params
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    /// application/x-www-form-urlencoded 只保留 unreserved 字符，
    /// 中文关键词和 URL 里的逗号必须转义，否则服务端解析出错。
    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
