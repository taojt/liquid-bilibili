import SwiftUI

@main
struct BiliGlassApp: App {
    /// 只用于把「当前允许的屏幕方向」传给 UIKit，全屏播放依赖它
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
