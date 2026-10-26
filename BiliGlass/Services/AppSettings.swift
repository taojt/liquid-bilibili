import SwiftUI

/// 应用级外观偏好。
///
/// 只负责「跟随系统 / 强制浅色 / 强制深色」这一个开关：
/// 具体每个颜色长什么样由 Asset Catalog 的 colorset 决定，
/// 这里只把 `preferredColorScheme` 塞给根视图。
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "白天"
            case .dark: return "夜间"
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.stars.fill"
            }
        }

        /// nil 表示交给系统
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private static let storageKey = "appAppearance"

    var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        // 调试口径：模拟器/真机没法脚本化点 chip，用一个不落盘的一次性开关验证
        // 「App 内主题覆盖系统主题」是否生效。正式使用时该键不存在。
        let debug = UserDefaults.standard.string(forKey: "debugAppearance") ?? ""
        if let forced = Appearance(rawValue: debug) {
            appearance = forced
            return
        }
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        appearance = Appearance(rawValue: stored) ?? .system
    }

    var colorScheme: ColorScheme? { appearance.colorScheme }
}
