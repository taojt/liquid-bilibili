import SwiftUI
import UIKit

/// 恢复系统「左滑返回」手势。
///
/// 详情页等用了 `navigationBarBackButtonHidden(true)` + 隐藏导航栏来搭自定义
/// 顶栏，SwiftUI 在导航栏隐藏时会把手势 delegate 换回内部实现并禁用，
/// 表现为「有自定义返回按钮的页面左滑没反应」。
///
/// 之前这版把 fix 挂在 `NavigationStack` 的 `.background` 上，靠
/// `vc.navigationController` 反查所属导航栈——但 `.background` 里的控制器
/// 并不在导航栈内部，`navigationController` 恒为 nil，patch 一次都没生效过。
/// 现在改成从 key window 往下遍历，把所有 `UINavigationController` 都装上。
///
/// 另外 SwiftUI 在每次 push/pop 后会重新设置 delegate，所以还要监听
/// `UINavigationControllerDidShowViewControllerNotification` 补装——
/// 这个通知名没有公开常量，只能用字符串。
struct PopGestureFix: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        DispatchQueue.main.async { PopGestureInstaller.install() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        PopGestureInstaller.install()
    }
}

enum PopGestureInstaller {
    private static var registered = false
    /// 最近一次装上的导航栈，delegate 在拿不到 view 时兜底用
    private(set) static weak var installedNav: UINavigationController?

    static func install() {
        registerObservers()
        guard let window = keyWindow() else { return }
        patchAll(from: window.rootViewController)
    }

    private static func registerObservers() {
        guard !registered else { return }
        registered = true
        let center = NotificationCenter.default
        let pushPop = Notification.Name("UINavigationControllerDidShowViewControllerNotification")
        center.addObserver(forName: pushPop, object: nil, queue: .main) { _ in install() }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            install()
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
    }

    private static func patchAll(from vc: UIViewController?) {
        guard let vc else { return }
        if let nav = vc as? UINavigationController {
            patch(nav)
        }
        for child in vc.children {
            patchAll(from: child)
        }
        if let presented = vc.presentedViewController {
            patchAll(from: presented)
        }
    }

    private static func patch(_ nav: UINavigationController) {
        guard let gesture = nav.interactivePopGestureRecognizer else { return }
        installedNav = nav
        // 只有真的被换回去时才算一次修复：push/pop 通知会高频触发 patch，
        // 无条件打印会把控制台刷满
        var repaired: String?
        if gesture.delegate !== PopGestureDelegate.shared {
            let name = gesture.delegate.map { String(describing: type(of: $0)) } ?? "nil"
            gesture.delegate = PopGestureDelegate.shared
            repaired = "delegate \(name) → PopGestureDelegate"
        }
        if !gesture.isEnabled {
            gesture.isEnabled = true
            repaired = (repaired.map { $0 + ", " } ?? "") + "enabled false → true"
        }
        if let repaired, DebugEntry.diag {
            print("[PopGesture] depth=\(nav.viewControllers.count) \(repaired)")
        }
    }
}

/// 栈深 > 1 才放行滑动：在根视图上响应边缘滑动会把导航栈滑出怪状态。
final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let nav = (gestureRecognizer.view as? UINavigationController)
            ?? gestureRecognizer.view?.nearestNavigationController()
            ?? PopGestureInstaller.installedNav
        guard let nav else { return false }
        return nav.viewControllers.count > 1
    }

    /// 与列表的纵向滚动、卡片点击共存。边缘手势和纵向滚动方向垂直，
    /// 同时识别不会互相抢；不显式放行的话，嵌套 ScrollView 里会直接失败。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private extension UIView {
    /// 沿 responder 链向上找所属的导航控制器
    func nearestNavigationController() -> UINavigationController? {
        var current: UIResponder? = self
        while let next = current?.next {
            if let nav = next as? UINavigationController { return nav }
            current = next
        }
        return nil
    }
}
