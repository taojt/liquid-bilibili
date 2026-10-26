import SwiftUI
import UIKit

/// 恢复系统「左滑返回」手势。
///
/// 详情页等用了 `navigationBarBackButtonHidden(true)` + 隐藏导航栏来搭自定义
/// 顶栏，SwiftUI 在导航栏隐藏时会顺带把 `interactivePopGestureRecognizer`
/// 的 delegate 换成内部实现并禁用手势，表现为「有自定义返回按钮的页面左滑没反应」。
///
/// 解法是把 delegate 换成自己的实现并重新启用。放在每个 `NavigationStack`
/// 根部各挂一份，patch 是幂等的。
struct PopGestureFix: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        DispatchQueue.main.async { Self.patch(from: vc) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // push/pop 之后 SwiftUI 可能重置 delegate，任何一次布局更新都重新 patch
        Self.patch(from: uiViewController)
    }

    private static func patch(from vc: UIViewController) {
        guard let nav = vc.navigationController,
              let gesture = nav.interactivePopGestureRecognizer else { return }
        if gesture.delegate !== PopGestureDelegate.shared {
            gesture.delegate = PopGestureDelegate.shared
        }
        if !gesture.isEnabled {
            gesture.isEnabled = true
        }
    }
}

/// 栈深 > 1 才放行滑动：在根视图上响应边缘滑动会把导航栈滑出怪状态。
final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = gestureRecognizer.view?.nearestNavigationController() else { return false }
        return nav.viewControllers.count > 1
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
