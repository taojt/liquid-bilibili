import SwiftUI
import UIKit

/// App 入口。
///
/// 为什么不是 `SwiftUI.App` + `@UIApplicationDelegateAdaptor`：那种写法下主屏快捷项
/// 收不到。实测（冷启动、热启动都试过）`performActionFor` 从不被调用，
/// `configurationForConnecting` 里的 `options.shortcutItem` 也恒为 nil——
/// 快捷项被 SwiftUI 自己的 scene delegate 吃掉了，而它没有公开 API 转发出来。
///
/// 所以入口改成 UIKit，自己指定 `SceneDelegate`，用 `UIHostingController`
/// 托住 `RootView`。SwiftUI 只负责界面，生命周期归我们管。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    /// scene 建立之前就能拿到快捷项（冷启动走这里）
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            ShortcutRouter.shared.handle(item)
        }
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// Scene 入口。
///
/// App 改成 UIKit 生命周期（原因见 `AppDelegate` 的注释）之后，window 由这里自己建，
/// SwiftUI 不再通过 `WindowGroup` 提供窗口，只靠 `UIHostingController` 托管 `RootView`。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let host = UIHostingController(rootView: RootView())
        // 底色由 RootView 里的 CanvasBackdrop 铺，这里留透明，避免启动瞬间闪一帧白
        host.view.backgroundColor = .clear

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window

        // 冷启动走快捷项时，item 挂在 scene 的连接选项上
        if let item = connectionOptions.shortcutItem {
            ShortcutRouter.shared.handle(item)
        }
    }

    /// App 已经活着（前台或后台）时点快捷项走这里
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        ShortcutRouter.shared.handle(shortcutItem)
        completionHandler(true)
    }
}
