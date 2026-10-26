import SwiftUI

/// 直播弹幕浮层。
///
/// 复用点播的 `DanmakuOverlay`——轨道调度、速度、字重、阴影全部一致，
/// 只把「时间源」换掉：点播用媒体时间，直播用「本次连接已建立的秒数」。
///
/// 时间源用 `TimelineView(.periodic)` 算，**不用** `Timer.publish`：
/// 后者作为 struct 的存储属性每次 view 重建都会新建一个 publisher，
/// 订阅随之重建，实际很难稳定触发（表现为弹幕停在第一帧不动）。
/// TimelineView 由系统托管调度，不存在这个问题。
struct LiveDanmakuOverlay: View {
    let bullets: [LiveBullet]
    /// 必须与 `LiveDanmakuClient.sessionStartedAt` 是同一个零点，否则时间轴整体偏移
    let startedAt: Date
    var fontSize: CGFloat = 14
    /// 顶部给控制条留出的空白
    var topInset: CGFloat = 0
    /// 不透明度与显示区域，跟随 `DanmakuSettings`
    var opacity: Double = 1
    var area: DanmakuArea = .full

    /// 锚点刷新频率。内层 `DanmakuOverlay` 自己按 30fps 在锚点之间外推，
    /// 所以这里只要够密就行，0.3 秒既平滑又不浪费。
    private let refreshInterval: TimeInterval = 0.3

    private var items: [DanmakuItem] {
        bullets.map(\.item)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            DanmakuOverlay(
                items: items,
                mediaTime: context.date.timeIntervalSince(startedAt),
                rate: 1,
                isPlaying: true,
                fontSize: fontSize,
                topInset: topInset,
                opacity: opacity,
                area: area
            )
        }
    }
}
