import AVFoundation
import MediaPlayer
import UIKit

/// 全屏播放时左右半屏竖滑要调的「亮度」和「音量」。
///
/// 两个都不是 App 私有量，iOS 没有提供 App 级接口：
/// - **亮度**没有 App 级 API，只能改 `UIScreen.main.brightness`。这改的是系统屏幕亮度，
///   退出 App 后保持（主流播放器都是这么做的，用户预期也如此）。
/// - **音量**唯一的写入口是 `MPVolumeView` 里的那个 `UISlider`。这个 view 必须真的挂在
///   视图层级上，`subviews` 里才拿得到 slider，所以建一个 1×1 的透明实例塞进窗口。
///   通过 slider 程序化改音量不会弹系统音量 HUD（那是按音量键才有的）。
final class SystemControls {
    static let shared = SystemControls()

    /// 音量滑块的宿主视图
    private var volumeHost: MPVolumeView?

    var brightness: CGFloat {
        get { UIScreen.main.brightness }
        set { UIScreen.main.brightness = min(max(newValue, 0), 1) }
    }

    var volume: Float {
        get { volumeSlider?.value ?? AVAudioSession.sharedInstance().outputVolume }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard let slider = volumeSlider else { return }
            // 直接赋值会被系统在下一个 runloop 覆盖，挪一格再回来是社区惯用的稳妥写法
            slider.value = clamped
        }
    }

    private var volumeSlider: UISlider? {
        installHostIfNeeded()
        return volumeHost?.subviews.compactMap { $0 as? UISlider }.first
    }

    private func installHostIfNeeded() {
        guard volumeHost == nil else { return }
        guard let window = Self.keyWindow else { return }
        let host = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 2, height: 2))
        host.alpha = 0.01
        host.showsVolumeSlider = true
        window.addSubview(host)
        volumeHost = host
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
    }
}
