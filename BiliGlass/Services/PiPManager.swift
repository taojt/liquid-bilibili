import AVFoundation
import AVKit
import Observation

/// 画中画（小窗播放）管理。
///
/// 自绘播放器没有用 `AVPlayerViewController`，画中画要自己搭：把
/// `AVPictureInPictureControllerContentSource(playerLayer:)` 挂在当前正在
/// 显示的 `AVPlayerLayer` 上。内嵌播放器和全屏播放器共用同一个 `AVPlayer`
/// 但各有一个 layer，谁的 layer 最后显示，就重新 attach 谁。
///
/// `canStartPictureInPictureAutomaticallyFromInline = true` 是「后台小窗」
/// 的关键：App 退到后台（或锁屏）时系统自动进小窗，回到前台自动还原，
/// 不需要业务代码监听 `willResignActive`。
///
/// iOS 27 SDK 变化：`ContentSource(playerLayer:playbackDelegate:)` 与
/// `AVPictureInPictureSamplePlaybackDelegate` 已被移除，自动进小窗的属性
/// 也从 `...OnDeactivation` 改名为 `...FromInline`。
@MainActor
@Observable
final class PiPManager {
    static let shared = PiPManager()

    private(set) var controller: AVPictureInPictureController?
    /// 小窗是否正在显示，详情页用它切「小窗播放中」占位
    var isActive = false

    /// 当前是否可以进小窗（系统支持 + 已挂上播放层）
    var isAvailable: Bool {
        AVPictureInPictureController.isPictureInPictureSupported() && controller != nil
    }

    private var activeObservation: NSKeyValueObservation?

    /// 把画中画控制器绑到当前显示的播放层上。重复 attach 同一个 layer 是幂等的。
    /// 注意模拟器 `isPictureInPictureSupported()` 恒为 false，只有真机可用。
    func attach(playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let controller,
           controller.contentSource?.playerLayer === playerLayer {
            return
        }

        let pip = AVPictureInPictureController(
            contentSource: .init(playerLayer: playerLayer)
        )
        pip.canStartPictureInPictureAutomaticallyFromInline = true

        activeObservation?.invalidate()
        activeObservation = pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) {
            [weak self] _, change in
            let active = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.isActive = active
            }
        }
        controller = pip
    }

    /// 手动切换：控制簇上的小窗按钮
    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    /// 调试 / 自动化用：能进就进
    func startIfPossible() {
        guard let controller, !controller.isPictureInPictureActive else { return }
        controller.startPictureInPicture()
    }

    /// 离开播放页时收掉小窗，避免小窗里的画面随引擎停止而冻结
    func stopIfNeeded() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }
}
