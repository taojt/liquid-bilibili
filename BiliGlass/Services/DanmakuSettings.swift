import SwiftUI

/// 弹幕显示偏好。
///
/// 只放两件与「看感」直接相关的事：不透明度和显示区域。
/// 字号、速度这些暂时不做——在手机上调节它们的收益远不如这两个明显。
///
/// 存在 `UserDefaults` 里，点播与直播共用同一份设置：
/// 用户调节的是「我看弹幕的习惯」，不该分场景各存一套。
@MainActor
@Observable
final class DanmakuSettings {
    static let shared = DanmakuSettings()

    private static let opacityKey = "danmakuOpacity"
    private static let areaKey = "danmakuArea"

    /// 0.2 ～ 1.0。低于 0.2 基本看不见，没有意义；不做到 0，那是「关闭弹幕」的语义。
    static let opacityRange: ClosedRange<Double> = 0.2...1.0

    var opacity: Double {
        didSet {
            UserDefaults.standard.set(opacity, forKey: Self.opacityKey)
        }
    }

    var area: DanmakuArea {
        didSet {
            UserDefaults.standard.set(area.rawValue, forKey: Self.areaKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.opacityKey) != nil {
            opacity = Swift.min(Self.opacityRange.upperBound,
                                Swift.max(Self.opacityRange.lowerBound, defaults.double(forKey: Self.opacityKey)))
        } else {
            opacity = 1.0
        }
        let storedArea = defaults.string(forKey: Self.areaKey) ?? ""
        area = DanmakuArea(rawValue: storedArea) ?? .full

        // 调试覆盖：模拟器里点不了滑杆和 chip，用启动键直接把设置摆到目标状态，
        // 才能截图验证三种区域和不透明度的真实渲染。正式使用这些键不存在。
        if let text = DebugEntry.danmakuArea, let target = DanmakuArea(rawValue: text) {
            area = target
        }
        if let value = DebugEntry.danmakuOpacity {
            opacity = Swift.min(Self.opacityRange.upperBound,
                                Swift.max(Self.opacityRange.lowerBound, value))
        }
    }

    /// 百分比文案，用于滑杆右侧的数值
    var opacityText: String {
        "\(Int((opacity * 100).rounded()))%"
    }

    var isDefault: Bool {
        area == .full && abs(opacity - 1.0) < 0.001
    }

    func reset() {
        opacity = 1.0
        area = .full
    }
}

/// 弹幕显示区域。
///
/// 单独放成顶层类型，而不是嵌在 `DanmakuSettings` 里：
/// 内嵌在一个 `@MainActor` 类中的类型，出现在 View 的默认参数位置时
/// 会被隔离检查牵连，写成顶层最省事。
enum DanmakuArea: String, CaseIterable, Identifiable {
    case full
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "全屏"
        case .top: return "上半区"
        case .bottom: return "下半区"
        }
    }

    var icon: String {
        switch self {
        case .full: return "rectangle.fill"
        case .top: return "rectangle.topthird.inset.filled"
        case .bottom: return "rectangle.bottomthird.inset.filled"
        }
    }

    /// 给设置面板用的示意图：区域在整屏里的相对位置（0~1）
    var verticalRange: ClosedRange<Double> {
        switch self {
        case .full: return 0.0...1.0
        case .top: return 0.0...0.5
        case .bottom: return 0.5...1.0
        }
    }
}
