import Observation
import SwiftUI

/// 悬浮底栏显隐闸门。
///
/// RootView 只负责画底栏；要不要藏由「被 push 上来的页面」自己声明：
/// 页面出现时登记自己所在的 Tab，消失时注销；当前 Tab 有登记页面就藏。
///
/// 为什么不用 `NavigationPath.count` 判断：view 版 `NavigationLink`
/// （destination 直接给视图的那种）**不会**写进绑定的 path，只有 value 版
/// `NavigationLink` / `navigationDestination(for:)` 会。而本项目的导航全是
/// view 版，path 永远是 0，靠它判断底栏就会一直盖在详情页 / 全屏播放上。
///
/// 为什么用「token 字典」而不是布尔量：详情页 → UP 主主页 → 再进一个详情页
/// 这种连续 push 时，新页面的 onAppear 早于旧页面的 onDisappear，布尔量会被
/// 旧页面的注销误清掉。每个页面拿独立的 token，互不干扰。
@Observable
final class FloatingTabGate {
    static let shared = FloatingTabGate()
    private(set) var residents: [UUID: Int] = [:]

    /// 页面出现时登记；token 是每个页面实例独立的身份
    func register(_ token: UUID, in tab: Int) {
        residents[token] = tab
    }

    /// 页面消失时注销
    func release(_ token: UUID) {
        residents.removeValue(forKey: token)
    }

    /// 指定 Tab 里是否还压着被 push 的页面
    func isCovered(_ tab: Int) -> Bool {
        residents.values.contains(tab)
    }
}

private struct RootTabIndexKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// 页面所属的根部 Tab 序号，push 页面登记时读取
    var rootTabIndex: Int {
        get { self[RootTabIndexKey.self] }
        set { self[RootTabIndexKey.self] = newValue }
    }
}

private struct FloatingTabGateModifier: ViewModifier {
    @State private var token = UUID()
    @Environment(\.rootTabIndex) private var tabIndex

    func body(content: Content) -> some View {
        content
            .onAppear { FloatingTabGate.shared.register(token, in: tabIndex) }
            .onDisappear { FloatingTabGate.shared.release(token) }
    }
}

extension View {
    /// 被 push 上来的页面加上它，悬浮底栏会自动收起
    func hidesFloatingTabBar() -> some View {
        modifier(FloatingTabGateModifier())
    }
}
