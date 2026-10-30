import SwiftUI

/// 按设备形态分档的布局参数。
///
/// 这个 App 原本是 iPhone 专用（`TARGETED_DEVICE_FAMILY = 1`），
/// 所有尺寸都按 393pt 宽的手机调。开到 iPad、再算上横竖屏之后有三处会明显不对：
///
/// 1. 封面网格固定 2 列 —— iPad 横屏每张封面近 600pt，一张卡占半屏；
/// 2. 悬浮底栏满宽 —— 4 个标签平摊到 1200pt，点一下要横跨半个屏幕；
/// 3. 正文满宽 —— 一行字横跨整个屏幕，眼睛要来回扫。
///
/// 列数用 `GridItem(.adaptive:)` 让系统按可用宽度自己算，
/// 不写死「iPhone 2 列 / iPad 4 列」——那样一旋转屏幕就又错了。
enum DeviceLayout {
    /// 封面网格列定义。
    ///
    /// `adaptive` 的列宽按可用宽度均分，实测：
    /// iPhone 竖屏 393pt → 2 列；iPad 竖屏 834pt → 4 列；iPad 横屏 1194pt → 6 列。
    /// 一开始按 `horizontalSizeClass` 写死 4 列，横屏下每列 290pt，封面大得离谱。
    static func coverGrid(spacing: CGFloat = 12, minimum: CGFloat = 160) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing)]
    }

    /// 悬浮底栏最大宽度。iPad 上再宽就不像"一条栏"而像"一条带"
    static let maxTabBarWidth: CGFloat = 460

    /// 正文内容最大宽度。iPad 上整页铺满会让一段文字横跨一整屏，
    /// 阅读时眼睛要来回扫，比手机还累。
    ///
    /// 取 760 而不是更宽：iPad 11 寸竖屏是 834pt，上限设 820 只剩 7pt 留白，
    /// 等于没做；760 能让两侧留出约 37pt，既压住行长又不会显得被"掏空"。
    static let maxContentWidth: CGFloat = 760

    /// 播放器在宽屏上的最大高度占比。
    ///
    /// iPad 横屏 1194pt 宽时 16:9 播放器高 672pt，占掉 834pt 屏高的八成，
    /// 底下的标题和评论几乎看不见。压到 0.62 后播放器仍是画面主体，
    /// 但下方能露出内容，不用一进来就得滚。
    static let playerMaxHeightRatio: CGFloat = 0.62

    /// 当前窗口尺寸。取活跃 scene 的 screen，而不是已弃用的 `UIScreen.main`
    static var screenSize: CGSize {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen.bounds.size ?? CGSize(width: 393, height: 852)
    }

    /// 横屏时播放器的高度上限；竖屏返回 nil（不限高）
    static var playerHeightLimit: CGFloat? {
        let size = screenSize
        guard size.width > size.height * 1.3 else { return nil }
        return size.height * playerMaxHeightRatio
    }
}

extension View {
    /// 限制内容宽度并在宽屏上居中。iPhone 上宽度本来就小于上限，等于没做事
    func readableWidth(_ maxWidth: CGFloat = DeviceLayout.maxContentWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
