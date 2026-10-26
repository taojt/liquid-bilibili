import SwiftUI

/// 弹幕浮动层。
///
/// 时间源有两个：`mediaTime` 来自 AVPlayer 的周期观察者（0.4 秒一次，够驱动进度条但不够动画面），
/// 因此这里用 `TimelineView` 按 30fps 自转，并用「基准时间 + 墙上时钟差 × 倍速」做外推，
/// 每次 `mediaTime` 更新就把基准重置回来，避免误差累积。
///
/// 暂停时 TimelineView 停止推进，画面自然冻结在当前帧。
struct DanmakuOverlay: View {
    let items: [DanmakuItem]
    let mediaTime: Double
    let rate: Float
    let isPlaying: Bool
    var fontSize: CGFloat = 15
    /// 顶部为常驻控件预留的空白。竖屏内嵌播放器的控制簇一直显示，
    /// 弹幕压上去会互相糊住，所以从控件下方开始排轨道。
    var topInset: CGFloat = 0
    /// 整体不透明度（0.2 ～ 1.0），由 `DanmakuSettings` 提供
    var opacity: Double = 1
    /// 显示区域：全屏 / 上半区 / 下半区
    var area: DanmakuArea = .full

    @State private var track: DanmakuTrack?
    @State private var anchorMedia: Double = 0
    @State private var anchorWall = Date()

    private let laneHeight: CGFloat = 30

    /// 诊断开关在初始化时读一次即可，别放进 30fps 的渲染体里反复查 UserDefaults
    private let showsDebugInfo = DebugEntry.danmakuInfo

    var body: some View {
        GeometryReader { geo in
            let region = laneRegion(for: geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                content(
                    size: geo.size,
                    region: region,
                    time: displayTime(context.date)
                )
            }
            .task(id: rebuildKey(width: geo.size.width, region: region)) {
                track = DanmakuTrack.build(
                    items: items,
                    screenWidth: geo.size.width,
                    lanes: region.lanes
                )
            }
            .overlay(alignment: .topLeading) {
                if showsDebugInfo {
                    Text("\(Int(geo.size.width))x\(Int(geo.size.height)) top=\(Int(region.top)) lanes=\(region.lanes) items=\(items.count) scroll=\(track?.scrolling.count ?? -1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(3)
                        .background(.black.opacity(0.7))
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear {
            anchorMedia = mediaTime
            anchorWall = Date()
        }
        .onChange(of: mediaTime) { _, latest in
            anchorMedia = latest
            anchorWall = Date()
        }
    }

    // MARK: - 时间

    private func displayTime(_ now: Date) -> Double {
        guard isPlaying else { return anchorMedia }
        // 观察者 0.4 秒一跳，外推最多 1 秒，避免卡顿时弹幕飞出去
        let delta = Swift.min(now.timeIntervalSince(anchorWall), 1.0)
        return anchorMedia + delta * Double(rate)
    }

    // MARK: - 轨道区域

    /// 可用轨道窗口：起点 y 与轨道条数。
    ///
    /// 「显示区域」只改窗口，不改调度逻辑——上半区就是可用高度折半、
    /// 轨道数跟着减半；下半区则把窗口整体下移。这样滚动、防重叠、
    /// 丢弃策略全都不用重写。
    struct LaneRegion: Equatable {
        let top: CGFloat
        let lanes: Int
    }

    private func laneRegion(for height: CGFloat) -> LaneRegion {
        let usable = Swift.max(0, height - 18 - topInset)
        let maxLanes = Int(usable / laneHeight)

        func clamp(_ value: Int) -> Int {
            Swift.max(1, Swift.min(9, value))
        }

        switch area {
        case .full:
            return LaneRegion(top: topInset, lanes: clamp(maxLanes))
        case .top:
            return LaneRegion(top: topInset, lanes: clamp(maxLanes / 2))
        case .bottom:
            let lanes = clamp(maxLanes / 2)
            // 贴着下半区底边往上排，留一点边距避免压到进度条
            let top = topInset + usable - CGFloat(lanes) * laneHeight - 4
            return LaneRegion(top: Swift.max(topInset, top), lanes: lanes)
        }
    }

    private func rebuildKey(width: CGFloat, region: LaneRegion) -> String {
        "\(Int(width))x\(region.lanes)x\(Int(region.top))-\(items.count)"
    }

    // MARK: - 绘制

    private func content(size: CGSize, region: LaneRegion, time: Double) -> some View {
        ZStack(alignment: .topLeading) {
            if let track {
                ForEach(track.active(at: time)) { scheduled in
                    scrolling(scheduled, size: size, region: region, time: time)
                }
                ForEach(track.pinnedActive(at: time)) { item in
                    pinned(item, size: size, region: region, time: time)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private func scrolling(
        _ scheduled: ScheduledDanmaku,
        size: CGSize,
        region: LaneRegion,
        time: Double
    ) -> some View {
        let speed = DanmakuTrack.speed(for: size.width)
        let elapsed = time - scheduled.item.time
        let x = size.width - CGFloat(elapsed) * speed
        return Text(scheduled.item.text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(scheduled.item.color)
            .shadow(color: .black.opacity(0.85), radius: 1.4)
            .fixedSize()
            .offset(x: x, y: region.top + CGFloat(scheduled.lane) * laneHeight + 7)
    }

    private func pinned(
        _ item: DanmakuItem,
        size: CGSize,
        region: LaneRegion,
        time: Double
    ) -> some View {
        let elapsed = time - item.time
        // 后 1 秒淡出，避免突然消失
        let fade = Swift.max(0, Swift.min(1, 4 - elapsed))
        // 顶部固定弹幕跟着窗口顶部走；底部固定弹幕贴着窗口底边，
        // 这样「只看上半区」时不会有一条孤零零落在屏幕最下方。
        let y: CGFloat
        if item.mode == 5 {
            y = region.top + 14
        } else {
            y = region.top + CGFloat(region.lanes) * laneHeight - 22
        }
        return Text(item.text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(item.color)
            .shadow(color: .black.opacity(0.85), radius: 1.4)
            .frame(width: size.width)
            .offset(y: Swift.max(0, y))
            .opacity(fade)
    }
}
