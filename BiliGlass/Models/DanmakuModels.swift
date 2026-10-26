import SwiftUI

// MARK: - 单条弹幕

struct DanmakuItem: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 出现时间（视频秒数，与 AVPlayer 的 currentTime 同一时基）
    let time: Double
    /// 1/2/3 滚动，4 底部固定，5 顶部固定
    let mode: Int
    /// 0xRRGGBB
    let colorValue: Int

    var isPinned: Bool { mode == 4 || mode == 5 }

    var color: Color {
        Color(
            red: Double((colorValue >> 16) & 0xFF) / 255,
            green: Double((colorValue >> 8) & 0xFF) / 255,
            blue: Double(colorValue & 0xFF) / 255
        )
    }
}

// MARK: - 已排轨道的弹幕

struct ScheduledDanmaku: Identifiable {
    let item: DanmakuItem
    let lane: Int
    let width: CGFloat
    let travelDuration: Double

    var id: Int { item.id }
}

// MARK: - 轨道调度

/// 把弹幕按时间排进若干条水平轨道。
///
/// 轨道分配只在「弹幕集合变化」时算一次，渲染时只做时间过滤 + 位移计算，
/// 这样 30fps 的动画开销与弹幕总量无关。
///
/// 关键约束：同一轨道里后一条必须等前一条的尾巴完全进入画面才能出发，
/// 否则两条会重叠。因为所有弹幕共用同一个速度，进入后不会互相追上，
/// 所以只需约束「出发时刻」。
struct DanmakuTrack {
    let scrolling: [ScheduledDanmaku]
    let pinned: [DanmakuItem]
    let screenWidth: CGFloat

    /// 全屏穿越时长：整屏宽度走完约 8 秒，这是弹幕观感的常用值
    static func speed(for width: CGFloat) -> CGFloat {
        Swift.max(60, width / 8)
    }

    static func build(
        items: [DanmakuItem],
        screenWidth: CGFloat,
        lanes: Int
    ) -> DanmakuTrack {
        guard screenWidth > 0, lanes > 0 else {
            return DanmakuTrack(scrolling: [], pinned: [], screenWidth: screenWidth)
        }
        let pxPerSecond = Self.speed(for: screenWidth)
        var laneAvailableAt = [Double](repeating: 0, count: lanes)
        var scrolling: [ScheduledDanmaku] = []
        var pinned: [DanmakuItem] = []

        for item in items.sorted(by: { $0.time < $1.time }) {
            if item.isPinned {
                pinned.append(item)
                continue
            }

            let width = estimatedWidth(item.text)
            var chosen = -1
            for lane in 0..<lanes where laneAvailableAt[lane] <= item.time {
                chosen = lane
                break
            }
            // 所有轨道都还占着就直接丢掉这一条：叠着显示比少一条更难看
            guard chosen >= 0 else { continue }

            laneAvailableAt[chosen] = item.time + Double((width + 18) / pxPerSecond)
            scrolling.append(
                ScheduledDanmaku(
                    item: item,
                    lane: chosen,
                    width: width,
                    travelDuration: Double((screenWidth + width) / pxPerSecond)
                )
            )
        }

        return DanmakuTrack(scrolling: scrolling, pinned: pinned, screenWidth: screenWidth)
    }

    /// 当前应出现在画面上的滚动弹幕
    func active(at time: Double) -> [ScheduledDanmaku] {
        guard !scrolling.isEmpty else { return [] }
        // 二分找到最后一条「还没到时间」的，然后往前回溯仍然存活的
        var low = 0
        var high = scrolling.count
        while low < high {
            let mid = (low + high) / 2
            if scrolling[mid].item.time <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var result: [ScheduledDanmaku] = []
        var index = low - 1
        while index >= 0 {
            let candidate = scrolling[index]
            let elapsed = time - candidate.item.time
            if elapsed > candidate.travelDuration { break }
            if elapsed >= 0 { result.append(candidate) }
            index -= 1
        }
        return result
    }

    func pinnedActive(at time: Double) -> [DanmakuItem] {
        guard !pinned.isEmpty else { return [] }
        return pinned.filter { time >= $0.time && time - $0.time <= 4 }
    }

    /// 估算文本像素宽度。CJK 按一个全角宽、ASCII 按约 0.56 个全角宽，
    /// 只用于轨道排布与进出场判断，几像素的误差不影响观感。
    static func estimatedWidth(_ text: String, fontSize: CGFloat = 15) -> CGFloat {
        var width: CGFloat = 0
        for scalar in text.unicodeScalars {
            width += scalar.value > 0x2E80 ? fontSize : fontSize * 0.56
        }
        return width
    }
}
