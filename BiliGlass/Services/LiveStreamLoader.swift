import Foundation
import AVFoundation

/// 为直播 HLS 注入防盗链请求头。
///
/// 和点播的 `HeaderResourceLoader` 不是一回事，原因在于 HLS 的分片是**子请求**：
/// 就算我们能给 m3u8 带上 header，AVFoundation 解析完播放列表后会自己去拉
/// `.ts` 分片，那些请求我们插不进去。
///
/// 好在这条链路的防盗链**只卡播放列表**：
///
/// ```
/// GET .../live_xxx.m3u8            无 Referer → 403，带 Referer → 200
/// GET .../live_xxx-1793013747.ts   无 Referer → 200
/// ```
///
/// 于是做法可以很简单：只把 m3u8 的 scheme 换成自定义的 `bili-live`，
/// 由本类接管；拿到文本后把里面所有**相对路径改写成绝对 https**，
/// 再交回去。分片和非播放列表资源都走原生 https，AVFoundation 自己拉，
/// 既不用逐块转发、也没有 Range 对齐问题。
///
/// 直播的播放列表是**持续刷新**的（每 4 秒一个新分片），AVFoundation 会反复
/// 请求同一个播放列表地址，每次都会进来这里重新拉一次最新内容。
final class LiveStreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = LiveStreamLoader()

    static let scheme = "bili-live"

    private static let referer = "https://live.bilibili.com/"

    private static let queue = DispatchQueue(label: "com.biliglass.live-loader")

    /// 生成能过防盗链的 HLS 资产
    static func makeAsset(_ url: URL) -> AVURLAsset {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        guard let proxied = components?.url else {
            return AVURLAsset(url: url)
        }
        let asset = AVURLAsset(url: proxied)
        asset.resourceLoader.setDelegate(shared, queue: queue)
        return asset
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url,
              let realURL = Self.originalURL(from: url)
        else { return false }

        var request = URLRequest(url: realURL)
        request.setValue(Self.referer, forHTTPHeaderField: "Referer")
        request.setValue(Self.referer, forHTTPHeaderField: "Origin")
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let isPlaylist = realURL.path.hasSuffix(".m3u8")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    loadingRequest.finishLoading(
                        with: NSError(
                            domain: "BiliGlass.LiveStream",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "直播流返回 \(http.statusCode)"]
                        )
                    )
                    return
                }

                var payload = data
                if isPlaylist, let text = String(data: data, encoding: .utf8) {
                    // 相对路径一律补成绝对地址，这样分片不经过我们也能拉
                    payload = Data(
                        Self.absolutize(playlist: text, baseURL: realURL).utf8
                    )
                }

                if let info = loadingRequest.contentInformationRequest {
                    info.isByteRangeAccessSupported = false
                    info.contentLength = Int64(payload.count)
                }
                loadingRequest.dataRequest?.respond(with: payload)
                loadingRequest.finishLoading()
            } catch {
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // 直播播放列表刷新时经常会把上一次请求取消掉，
        // 这里没有需要回收的 task（URLSession 的取消由超时兜底），留空即可
    }

    // MARK: - 工具

    private static func originalURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    /// 把播放列表里的相对 URI 全部换成绝对地址。
    ///
    /// 需要处理两种写法：
    /// - 独立的行：`live_xxx-1793013747.ts`
    /// - 标签属性：`#EXT-X-KEY:METHOD=AES-128,URI="key.key"`、`#EXT-X-MAP:URI="init.mp4"`
    static func absolutize(playlist: String, baseURL: URL) -> String {
        let lines = playlist.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        output.reserveCapacity(lines.count)

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                output.append(line)
                continue
            }

            if trimmed.hasPrefix("#") {
                output.append(rewriteAttributes(in: line, baseURL: baseURL))
                continue
            }

            output.append(absolute(trimmed, baseURL: baseURL) ?? trimmed)
        }

        return output.joined(separator: "\n")
    }

    /// 改写 `URI="..."` 形式的属性
    private static func rewriteAttributes(in line: String, baseURL: URL) -> String {
        guard line.contains("URI=") else { return line }

        var result = ""
        var remainder = Substring(line)

        while let range = remainder.range(of: "URI=\"") {
            result += remainder[remainder.startIndex..<range.upperBound]
            remainder = remainder[range.upperBound...]

            guard let end = remainder.firstIndex(of: "\"") else {
                result += remainder
                return result
            }
            let value = String(remainder[remainder.startIndex..<end])
            result += absolute(value, baseURL: baseURL) ?? value
            remainder = remainder[end...]
        }

        result += remainder
        return result
    }

    private static func absolute(_ value: String, baseURL: URL) -> String? {
        // 已经是绝对地址就不用动（B站偶尔会下发 CDN 绝对地址）
        if value.contains("://") { return value }
        guard let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return resolved.absoluteString
    }
}
