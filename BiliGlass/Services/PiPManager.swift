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
/// 两个关键点：
/// 1. 控制器**懒创建**。`makeUIView` 那一刻 layer 尺寸还是 0，此时创建的
///    content source 起不来小窗（`isPictureInPicturePossible` 恒为 false，
///    `startPictureInPicture()` 静默失败）。所以 attach 时先记住 layer，
///    等 layer 有了非零尺寸（layoutSubviews 后再 attach / 用户点按钮）才建控制器。
/// 2. `startPictureInPicture()` 要等 `isPictureInPicturePossible == true` 才会生效。
///    自动进小窗（退后台）会带一个 pending 标记，等 possible 翻 true 再补发。
///
/// `canStartPictureInPictureAutomaticallyFromInline = true` 是「后台小窗」
/// 的关键：App 退到后台（或锁屏）时系统自动进小窗，回到前台自动还原。
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

    /// 最近一次 attach 的播放层（weak：layer 随宿主 view 释放）
    private weak var currentLayer: AVPlayerLayer?
    /// 请求了起播但系统还没放行（isPictureInPicturePossible 尚为 false）
    private var pendingStart = false

    /// 当前是否可以进小窗（系统支持 + 已挂上播放层）
    var isAvailable: Bool {
        AVPictureInPictureController.isPictureInPictureSupported() && currentLayer != nil
    }

    private var activeObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?

    /// 把播放层登记给画中画管理器。重复 attach 同一个 layer 是幂等的。
    /// 注意模拟器 `isPictureInPictureSupported()` 恒为 false，只有真机可用。
    func attach(playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        currentLayer = playerLayer
        // layer 还没走完布局（尺寸为 0）时创建的 content source 起不来小窗，等下一轮
        guard playerLayer.bounds.width > 1, playerLayer.bounds.height > 1 else { return }
        if let controller,
           controller.contentSource?.playerLayer === playerLayer {
            return
        }
        makeController(playerLayer: playerLayer)
    }

    private func makeController(playerLayer: AVPlayerLayer) {
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

        // 系统放行小窗的时机不受我们控制（layer 可见 + 音频会话活跃），
        // 这里挂一个观察：一放行就把挂起的起播请求补发出去
        possibleObservation?.invalidate()
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
            [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor [weak self] in
                self?.flushPendingStart()
            }
        }

        controller = pip
    }

    /// 手动切换：控制簇上的小窗按钮
    func toggle() {
        prepare()
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            pendingStart = true
            flushPendingStart()
        }
    }

    /// 调试 / 自动化用：能进就进
    func startIfPossible() {
        prepare()
        guard let controller, !controller.isPictureInPictureActive else { return }
        pendingStart = true
        flushPendingStart()
    }

    /// 离开播放页时收掉小窗，避免小窗里的画面随引擎停止而冻结
    func stopIfNeeded() {
        pendingStart = false
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    private func prepare() {
        guard controller == nil, let layer = currentLayer else { return }
        guard layer.bounds.width > 1, layer.bounds.height > 1 else { return }
        makeController(playerLayer: layer)
    }

    private func flushPendingStart() {
        guard pendingStart, let controller, !controller.isPictureInPictureActive else { return }
        guard controller.isPictureInPicturePossible else { return }
        pendingStart = false
        controller.startPictureInPicture()
    }

    // MARK: - 诊断

    /// 调试用：把画中画的三态拼成一行，直接显示在界面上（真机没法读日志）
    var debugText: String {
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        guard let controller else { return "pip: no-ctl layer=\(currentLayer != nil) sup=\(supported)" }
        return "pip: sup=\(supported) pos=\(controller.isPictureInPicturePossible) act=\(controller.isPictureInPictureActive) pend=\(pendingStart)"
    }
}
