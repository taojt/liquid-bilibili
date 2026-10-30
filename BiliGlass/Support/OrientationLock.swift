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
    /// 是否在 iPad 上运行。iPad 的方向策略与手机完全不同：
    /// 用户会把它当一块"屏幕"横着用，锁竖屏的结果是横屏时 App 只占中间一条、
    /// 两侧露出桌面——看起来就像"没适配横屏"。
    private static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// 非播放页时的默认方向。iPhone 锁竖屏；iPad 全程放开，
    /// 布局靠 `DeviceLayout` 的自适应列数兜住。
    private static var idleMask: UIInterfaceOrientationMask {
        isPad ? .all : .portrait
    }

    /// 由 AppDelegate 读取。
    static var mask: UIInterfaceOrientationMask = idleMask

    /// 放开旋转（详情页/直播页驻留期间调用）
    static func allowRotation() {
        mask = .allButUpsideDown
        refreshSupportedOrientations()
    }

    /// 锁回默认方向，并把界面转回去（离开播放页时调用）。
    /// iPad 上只恢复 mask、不主动转屏：用户可能正横着看列表，
    /// 强行转回竖屏会把整页内容甩一下。
    static func lockPortrait() {
        mask = idleMask
        refreshSupportedOrientations()
        guard !isPad else { return }
        request(.portrait)
    }

    /// 手动进入全屏：请求横屏。
    /// mask 保持放开，这样用户在横屏里再把手机转回竖屏，依然能自动退出全屏。
    static func forceLandscape() {
        mask = .allButUpsideDown
        refreshSupportedOrientations()
        request(preferredLandscape())
    }

    /// 手动退出全屏：请求竖屏。
    /// iPad 上退出全屏只是收起播放层，方向保持用户当前握持的方向。
    static func forcePortrait() {
        mask = idleMask
        refreshSupportedOrientations()
        guard !isPad else { return }
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
