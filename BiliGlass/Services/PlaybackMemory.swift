import Foundation

/// 本地播放进度记忆。
///
/// B站的 `history/cursor` 接口本身会返回 progress，但只有「真正被服务端记下」的视频才有，
/// 而且换设备/未登录就丢了。这里再存一份本地记录，保证任何入口进来的视频都能断点续播。
enum PlaybackMemory {
    private static let prefix = "resume."
    private static let defaults = UserDefaults.standard

    /// 续播点太靠前没有意义，太靠后说明已经看完，都不该自动跳
    private static let minPosition = 5
    private static let tailGuard = 12

    /// 读取断点，返回 nil 表示应当从头播放
    static func position(for bvid: String, duration: Int? = nil) -> Int? {
        guard !bvid.isEmpty else { return nil }
        let stored = defaults.object(forKey: prefix + bvid) as? [String: Int]
        guard let record = stored, let position = record["position"], position >= minPosition else {
            return nil
        }
        let total = duration ?? record["duration"] ?? 0
        if total > 0, position >= total - tailGuard { return nil }
        return position
    }

    static func save(bvid: String, position: Int, duration: Int) {
        guard !bvid.isEmpty, position > 0 else { return }
        if duration > 0, position >= duration - tailGuard {
            // 已经看完，清掉记录，下次从头开始
            defaults.removeObject(forKey: prefix + bvid)
            return
        }
        defaults.set(["position": position, "duration": duration], forKey: prefix + bvid)
    }

    static func clear(bvid: String) {
        defaults.removeObject(forKey: prefix + bvid)
    }
}
