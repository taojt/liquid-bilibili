import Observation
import UIKit

/// 主屏图标快捷入口。
///
/// 这是 iOS 的 Home Screen Quick Actions：老机型（iPhone XS 及以前）是重按图标的
/// 3D Touch，新机型是长按触发的 Haptic Touch，**系统层面是同一套机制**，
/// 都从 `UIApplicationShortcutItem` 进来，所以一份实现同时覆盖两种交互。
///
/// 条目在 Info.plist 的 `UIApplicationShortcutItems` 里静态声明——静态项的好处是
/// 进程还没起来时 SpringBoard 也能画出来；代价是顺序固定（系统按数组顺序展示）。
enum ShortcutAction: String, CaseIterable {
    /// 打开搜索页并直接聚焦输入框
    case search
    /// 回到首页并切到「热门」二级 Tab
    case hot

    /// Info.plist 里写的 type。用 bundle id 前缀是全 App 的约定，
    /// 解析时只认最后一段，这样改 bundle id 不至于把快捷项全废掉。
    static let typePrefix = "com.biliglass.app.shortcut."

    var typeIdentifier: String { Self.typePrefix + rawValue }

    init?(type: String) {
        guard let last = type.split(separator: ".").last else { return nil }
        self.init(rawValue: String(last))
    }
}

/// 快捷项的落地路由。
///
/// 分发点在 `SceneDelegate` 里，两个都要接：冷启动时 item 挂在
/// `scene(_:willConnectTo:options:)` 的 `connectionOptions.shortcutItem` 上；
/// 已经在前台/后台时走 `windowScene(_:performActionFor:)`。
///
/// （SwiftUI 的 App 生命周期这两条都收不到——快捷项被它自己的 scene delegate
/// 吃掉了，所以整个入口改成了 UIKit，详见 README「主屏快捷入口」。）
///
/// 存下来的动作由 RootView 切 Tab、HomeView 真正执行，执行完必须 `consume()`，
/// 否则下次切 Tab 重建视图会重放一次。
@Observable
final class ShortcutRouter {
    static let shared = ShortcutRouter()

    /// 待落地的动作。为 nil 表示没有挂起的快捷项
    private(set) var pending: ShortcutAction?

    func handle(_ item: UIApplicationShortcutItem) {
        guard let action = ShortcutAction(type: item.type) else { return }
        pending = action
    }

    func consume() {
        pending = nil
    }

    /// 调试注入：`-debugShortcut search|hot`，跳过 SpringBoard 直接验证落地路由。
    /// 主屏长按图标没法用脚本触发（要跨进程操作 SpringBoard），这条通路让
    /// 路由逻辑本身可以被单独验证。
    func inject(_ action: ShortcutAction) {
        pending = action
    }
}
