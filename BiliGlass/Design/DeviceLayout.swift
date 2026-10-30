import SwiftUI

/// 按设备形态分档的布局参数。
///
/// 这个 App 原本是 iPhone 专用（`TARGETED_DEVICE_FAMILY = 1`），
/// 所有尺寸都按 393pt 宽的手机调。开到 iPad 后有两处会明显不对：
///
/// 1. 封面网格固定 2 列 —— iPad 横屏每张封面近 600pt，一张卡占半屏；
/// 2. 悬浮底栏满宽 —— 4 个标签平摊到 1200pt，点一下要横跨半个屏幕。
///
/// 所以列数和栏宽都按 `horizontalSizeClass` 分档，iPhone 上的取值
/// 与改动前完全一致，不影响原有手感。
enum DeviceLayout {
    /// 封面网格列数：iPhone(compact) 2 列；iPad(regular) 4 列
    static func coverColumns(_ sizeClass: UserInterfaceSizeClass?) -> Int {
        sizeClass == .regular ? 4 : 2
    }

    /// 封面网格的列定义
    static func coverGrid(_ sizeClass: UserInterfaceSizeClass?, spacing: CGFloat = 12) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: coverColumns(sizeClass)
        )
    }

    /// 悬浮底栏最大宽度。iPad 上再宽就不像"一条栏"而像"一条带"
    static let maxTabBarWidth: CGFloat = 460

    /// 正文内容最大宽度。iPad 上整页铺满会让一段文字横跨一整屏，
    /// 阅读时眼睛要来回扫，比手机还累。
    ///
    /// 取 760 而不是更宽：iPad 11 寸竖屏是 834pt，上限设 820 只剩 7pt 留白，
    /// 等于没做；760 能让两侧留出约 37pt，既压住行长又不会显得被"掏空"。
    static let maxContentWidth: CGFloat = 760
}

extension View {
    /// 限制内容宽度并在宽屏上居中。iPhone 上宽度本来就小于上限，等于没做事
    func readableWidth(_ maxWidth: CGFloat = DeviceLayout.maxContentWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
