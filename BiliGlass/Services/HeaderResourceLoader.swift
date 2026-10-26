import Foundation
import AVFoundation

/// 为 AVPlayer 注入防盗链请求头。
///
/// 两件事必须自己做：
/// 1. `AVURLAssetHTTPHeaderFieldsKey` 这个非公开 option 在 iOS 27 上已经失效，
///    带自定义 header 的资产直接报 "Cannot Open"，只能靠 ResourceLoader 接管。
/// 2. AVFoundation 首次会请求极大区间（往往就是整个文件），若等 dataTask 全部
///    下载完再回调必然超时，因此这里用 URLSession delegate 逐块 respond。
final class HeaderResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = HeaderResourceLoader()

    static let videoScheme = "bili-video"
    static let audioScheme = "bili-audio"
    static let queue = DispatchQueue(label: "com.biliglass.resource-loader")

    /// 单次最多回给 AVFoundation 的字节数。设得过大等于按需把整段视频拖下来，
    /// 设得过小又会让 AVFoundation 收到的字节少于 requestedLength 而卡住，
    /// 因此这里不主动截断，只在极端情况下用一个很高的上限兜底。
    private static let maxChunk: Int = 96 * 1024 * 1024

    private final class Pending {
        let request: AVAssetResourceLoadingRequest
        let expected: Int
        var responded: Int = 0
        var finished = false

        init(request: AVAssetResourceLoadingRequest, expected: Int) {
            self.request = request
            self.expected = expected
        }
    }

    private var pending: [Int: Pending] = [:]

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        // 与 resourceLoader 的 delegate queue 复用同一条串行队列，
        // 这样 pending 字典的读写天然串行，无需额外加锁
        let opQueue = OperationQueue()
        opQueue.underlyingQueue = HeaderResourceLoader.queue
        opQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: cfg, delegate: self, delegateQueue: opQueue)
    }()

    /// 生成带 header 注入能力的资产
    static func makeAsset(_ url: URL, isAudio: Bool) -> AVURLAsset {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = isAudio ? audioScheme : videoScheme
        guard let proxied = comps?.url else {
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
        guard let url = loadingRequest.request.url else { return false }
        let isAudio = url.scheme == Self.audioScheme

        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        comps.scheme = "https"
        guard let realURL = comps.url else { return false }

        var request = URLRequest(url: realURL)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")

        // 把 AVFoundation 的字节需求翻译成 HTTP Range
        var expected = 0
        if let dataRequest = loadingRequest.dataRequest, dataRequest.requestedLength > 0 {
            let start = dataRequest.requestedOffset
            let want = min(dataRequest.requestedLength, Self.maxChunk)
            expected = want
            request.setValue("bytes=\(start)-\(start + Int64(want) - 1)", forHTTPHeaderField: "Range")
        }

        let task = session.dataTask(with: request)
        pending[task.taskIdentifier] = Pending(request: loadingRequest, expected: expected)
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // 找到对应 task 并取消，避免继续下载
        for (id, item) in pending where item.request === loadingRequest {
            item.finished = true
            pending.removeValue(forKey: id)
            break
        }
    }
}

// MARK: - URLSession 回调

extension HeaderResourceLoader: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let item = pending[dataTask.taskIdentifier],
              let http = response as? HTTPURLResponse,
              !item.request.isCancelled
        else {
            completionHandler(.cancel)
            return
        }

        let isAudio = item.request.request.url?.scheme == Self.audioScheme
        if let info = item.request.contentInformationRequest {
            info.contentType = isAudio ? "public.mpeg-4-audio" : "public.mpeg-4"
            info.isByteRangeAccessSupported = true
            if let total = Self.totalLength(from: http) {
                info.contentLength = total
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let item = pending[dataTask.taskIdentifier], !item.finished else { return }
        guard let dataRequest = item.request.dataRequest, !item.request.isCancelled else { return }

        // 不限长度（expected == 0）时一直跟随 HTTP 响应直到自然结束
        let remaining = item.expected > 0 ? item.expected - item.responded : Int.max
        guard remaining > 0 else {
            // 已经满足 AVFoundation 本次的请求量，收尾让它重新发起下一段
            finish(item, taskID: dataTask.taskIdentifier)
            dataTask.cancel()
            return
        }

        let slice = data.count > remaining ? data.prefix(remaining) : data
        dataRequest.respond(with: Data(slice))
        item.responded += slice.count

        if item.expected > 0, item.responded >= item.expected {
            finish(item, taskID: dataTask.taskIdentifier)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = pending[task.taskIdentifier] else { return }
        if item.finished { return }

        if let error {
            // 主动取消导致的失败不算错误
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                finish(item, taskID: task.taskIdentifier)
            } else {
                item.request.finishLoading(with: error)
                pending.removeValue(forKey: task.taskIdentifier)
            }
            return
        }
        finish(item, taskID: task.taskIdentifier)
    }

    private func finish(_ item: Pending, taskID: Int) {
        guard !item.finished else { return }
        item.finished = true
        pending.removeValue(forKey: taskID)
        item.request.finishLoading()
    }

    /// 从 Content-Range 解析总长度，AVFoundation 靠它计算可 seek 的边界
    private static func totalLength(from response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let totalPart = range.split(separator: "/").last,
           let total = Int64(totalPart.trimmingCharacters(in: .whitespaces)) {
            return total
        }
        let expected = response.expectedContentLength
        return expected > 0 ? expected : nil
    }
}
