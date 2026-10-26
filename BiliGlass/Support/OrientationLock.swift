import UIKit

/// 屏幕方向锁定。
///
/// SwiftUI 没有公开的转屏 API，全屏播放需要走 UIKit：
/// 把「当前允许的方向」写进 AppDelegate 的 supportedInterfaceOrientations，
/// 需要主动转向时再调 `UIWindowScene.requestGeometryUpdate`。
///
/// 两种模式要分清：
/// - **自动旋转**：只要 mask 放开（`.allButUpsideDown`），用户转动手机系统就会自己转，
///   我们只需要跟着改布局，**不要**调 requestGeometryUpdate，否则会把内容强制到
///   某个固定方向，出现"手机转向左、画面转向右"的错位。
/// - **手动按钮**：用户点全屏/退出，才需要显式请求某个方向。
enum OrientationLock {
    /// 由 AppDelegate 读取。默认竖屏。
    static var mask: UIInterfaceOrientationMask = .portrait

    /// 放开旋转（详情页/直播页驻留期间调用）
    static func allowRotation() {
        mask = .allButUpsideDown
        refreshSupportedOrientations()
    }

    /// 锁回竖屏，并把界面转回竖屏（离开播放页时调用）
    static func lockPortrait() {
        mask = .portrait
        refreshSupportedOrientations()
        request(.portrait)
    }

    /// 手动进入全屏：请求横屏。
    /// mask 保持放开，这样用户在横屏里再把手机转回竖屏，依然能自动退出全屏。
    static func forceLandscape() {
        mask = .allButUpsideDown
        refreshSupportedOrientations()
        request(preferredLandscape())
    }

    /// 手动退出全屏：请求竖屏
    static func forcePortrait() {
        refreshSupportedOrientations()
        request(.portrait)
    }

    /// 如果手机已经横着，就顺着它；否则按右手持机的习惯给 landscapeRight。
    /// 注意 UIDeviceOrientation 与 UIInterfaceOrientation 的左右是**相反**的命名。
    private static func preferredLandscape() -> UIInterfaceOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return .landscapeRight
        }
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    private static func refreshSupportedOrientations() {
        activeScene?.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func request(_ orientation: UIInterfaceOrientation) {
        guard let scene = activeScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask(for: orientation))) { _ in
            // 失败（例如被其他控制器拦下）时保持原方向，不做重试：
            // 播放器本身不会因为方向不对而中断，只是观感问题。
        }
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        @unknown default: return .portrait
        }
    }
}

/// 只有这个 AppDelegate 存在的意义就是把方向锁暴露给 UIKit
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
