import SwiftUI

/// 视觉令牌：颜色、圆角、间距。
///
/// 颜色全部来自 Asset Catalog 的语义色（`CanvasTop` / `Ink` / `BrandPink` …），
/// 每个 colorset 自带 light / dark 两个变体，由系统按当前 trait 解析。
/// 这样主题切换时不需要任何 View 参与——`Color("Ink")` 会自动变成另一种墨色。
/// 如果把这些颜色写成 Swift 里的 static let，切主题时只有重新读取了
/// `@Environment(\.colorScheme)` 的视图会刷新，散落各处的调用点会拿到旧值。
enum Theme {
    // MARK: 品牌色
    static let pink = Color("BrandPink")
    static let blue = Color("BrandBlue")
    static let purple = Color("BrandPurple")

    // MARK: 文字 / 描边
    /// 主文字色。深色主题下是白，浅色主题下是近黑。
    /// 也直接当"墨"用于半透明填充（`ink.opacity(0.06)` 做卡片底），两套主题都成立。
    static let ink = Color("Ink")
    static let inkDim = Color("InkDim")
    static let inkFaint = Color("InkFaint")

    /// 卡片内容区的半透明底，比纯玻璃更"实"，保证长列表可读
    static var cardFill: Color { ink.opacity(0.06) }
    /// 卡片描边
    static var cardStroke: Color { ink.opacity(0.09) }

    // MARK: 圆角 / 间距
    /// 卡片圆角，与控件圆角保持同族曲线
    static let cardRadius: CGFloat = 26
    static let innerRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16

    /// 页面底色：浅色是带粉紫调的近白，深色是近黑紫蓝。
    /// 参考色取自 B站播放页的粉→蓝过渡，只是各自压到对应亮度。
    static var canvas: LinearGradient {
        LinearGradient(
            colors: [
                Color("CanvasTop"),
                Color("CanvasMid"),
                Color("CanvasBottom")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 卡片封面背后的柔和光斑，让玻璃折射有层次
    static func glow(for seed: String) -> RadialGradient {
        let palette: [Color] = [pink, blue, purple]
        let idx = abs(seed.hashValue) % palette.count
        return RadialGradient(
            colors: [palette[idx].opacity(0.55), .clear],
            center: .center,
            startRadius: 4,
            endRadius: 260
        )
    }
}

// MARK: - 格式化

extension Int {
    /// 播放量/弹幕量的中文缩写：12345 -> 1.2万
    var biliCount: String {
        switch self {
        case ..<0: return "0"
        case ..<10_000: return "\(self)"
        case ..<100_000_000:
            let v = Double(self) / 10_000
            return String(format: v >= 100 ? "%.0f万" : "%.1f万", v)
        default:
            let v = Double(self) / 100_000_000
            return String(format: "%.1f亿", v)
        }
    }

    /// 秒 -> 03:25 或 1:02:03
    var durationText: String {
        let s = Swift.max(0, self)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    /// 秒 -> 用于进度条旁的时钟显示
    var clockText: String {
        let s = Swift.max(0, Int(self))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    /// 生日时间戳 -> 05-20。
    /// B站生日只到「月日」，年份是占位值，所以不显示年。
    var birthdayText: String {
        guard self > 0 else { return "未设置" }
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    /// 评论时间戳 -> 刚刚 / 5分钟前 / 3小时前 / 2天前 / 2025-08-01
    ///
    /// 评论时间戳是**秒**级。超过 30 天就不好再折算成「多少天前」，
    /// 直接给日期更利于判断新旧。
    var relativeTimeText: String {
        guard self > 0 else { return "" }
        let now = Date().timeIntervalSince1970
        let delta = now - TimeInterval(self)
        // 服务端时钟可能略快于本地，出现负数按「刚刚」处理，别显示「-1分钟前」
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60))分钟前" }
        if delta < 86_400 { return "\(Int(delta / 3600))小时前" }
        if delta < 86_400 * 30 { return "\(Int(delta / 86_400))天前" }
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension String {
    /// B站封面常常以 // 开头或需要缩放参数
    var biliImageURL: URL? {
        var s = self
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") { s = s.replacingOccurrences(of: "http://", with: "https://") }
        return URL(string: s)
    }

    /// 封面加 @ 参数取缩略图，省流量
    func biliThumbnail(width: Int) -> URL? {
        guard var s = biliImageURL?.absoluteString else { return nil }
        if s.contains("@") { s = String(s.split(separator: "@")[0]) }
        return URL(string: "\(s)@\(width)w_\(width * 9 / 16)h_1c.webp")
    }
}
