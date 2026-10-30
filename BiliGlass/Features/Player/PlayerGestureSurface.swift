import SwiftUI
import UIKit

/// 播放区的手势：
///
/// - **长按**（0.4 秒）临时加速到 2×，松手立刻回到用户自己选的倍速
/// - **全屏时左右半屏竖滑**：左半屏调屏幕亮度、右半屏调系统音量
///
/// 为什么长按要自己计时而不是直接用 `onLongPressGesture` 的 `perform`：
/// 这里要的是「按住期间持续加速、松手马上恢复」，`perform` 只在识别成功那一刻回调一次，
/// 拿不到松开事件。用 `pressing:` 回调自己起一个 0.4 秒的计时器，松手取消/恢复，
/// 逻辑才闭合。
struct PlayerGestureModifier: ViewModifier {
    let engine: PlaybackEngine
    /// 只有全屏才启用亮度/音量竖滑（竖屏内嵌时滑动留给页面滚动）
    var systemGestures: Bool = false
    @Binding var hud: PlayerHUDKind?
    @Binding var hudValue: Double

    /// 长按加速的原始倍速，nil 表示当前没在加速
    @State private var restoreRate: Float?
    @State private var boostTask: Task<Void, Never>?
    @State private var hudHideTask: Task<Void, Never>?

    @State private var dragSide: DragSide?
    @State private var dragAnchor: Double = 0

    private enum DragSide { case brightness, volume }

    /// 满量程需要滑过屏幕高度的多少。0.72 大致是「从底滑到顶能走完一整段」的手感
    private let fullRangeRatio: CGFloat = 0.72

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 26, pressing: handlePressing, perform: {})
            // 必须用 simultaneousGesture：`.gesture` 是后加者优先，DragGesture
            // 在手指静止时一直停在「可能识别」而不失败，会把长按彻底饿死
            .simultaneousGesture(verticalDrag)
    }

    // MARK: - 长按倍速

    private func handlePressing(_ pressing: Bool) {
        DebugEntry.GestureLog.add("press \(pressing)")
        if pressing {
            boostTask?.cancel()
            boostTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                beginBoost()
            }
        } else {
            boostTask?.cancel()
            boostTask = nil
            endBoost()
        }
    }

    private func beginBoost() {
        guard engine.isReady else {
            DebugEntry.GestureLog.add("boost skip:notReady")
            return
        }
        guard engine.isPlaying else {
            DebugEntry.GestureLog.add("boost skip:paused")
            return
        }
        guard restoreRate == nil else {
            DebugEntry.GestureLog.add("boost skip:already")
            return
        }
        restoreRate = engine.playbackRate
        engine.boostCount += 1
        engine.applyTemporaryRate(2.0)
        DebugEntry.GestureLog.add("boost on rate=\(restoreRate ?? -1)")
        showHUD(.speed(2.0), value: 1)
    }

    private func endBoost() {
        guard let rate = restoreRate else { return }
        restoreRate = nil
        engine.applyTemporaryRate(rate)
        hideHUD()
    }

    // MARK: - 亮度 / 音量

    private var verticalDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged(handleDrag)
            .onEnded { _ in
                dragSide = nil
                hideHUD()
            }
    }

    private func handleDrag(_ gesture: DragGesture.Value) {
        guard systemGestures else { return }

        if dragSide == nil {
            // 只认竖直方向：横向滑动在播放区没有含义，放过去免得误触
            guard abs(gesture.translation.height) > abs(gesture.translation.width) * 1.2 else { return }
            // 用户开始拖了，说明不是长按
            boostTask?.cancel()
            boostTask = nil
            endBoost()

            let isLeft = gesture.startLocation.x < UIScreen.main.bounds.width / 2
            dragSide = isLeft ? .brightness : .volume
            dragAnchor = isLeft
                ? Double(SystemControls.shared.brightness)
                : Double(SystemControls.shared.volume)
            DebugEntry.GestureLog.add("drag begin \(isLeft ? "left" : "right") anchor=\(dragAnchor)")
        }

        guard let side = dragSide else { return }
        // 上滑变大（位移为负），除以满量程得到增量
        let span = max(1, screenHeight * fullRangeRatio)
        let delta = -gesture.translation.height / span
        let next = min(1, max(0, dragAnchor + Double(delta)))

        switch side {
        case .brightness:
            SystemControls.shared.brightness = CGFloat(next)
            // 读回实际值：拿不到可写的系统接口时这里会原样返回，自动化才能发现
            let applied = Double(SystemControls.shared.brightness)
            engine.lastBrightness = applied
            showHUD(.brightness, value: applied)
        case .volume:
            SystemControls.shared.volume = Float(next)
            let applied = Double(SystemControls.shared.volume)
            engine.lastVolume = applied
            showHUD(.volume, value: applied)
        }
    }

    private var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen.bounds.height ?? 800
    }

    // MARK: - HUD

    private func showHUD(_ kind: PlayerHUDKind, value: Double) {
        hudHideTask?.cancel()
        if hud != kind {
            withAnimation(.easeOut(duration: 0.12)) { hud = kind }
        }
        hudValue = value

        hudHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { hud = nil }
        }
    }

    private func hideHUD() {
        hudHideTask?.cancel()
        hudHideTask = nil
        withAnimation(.easeOut(duration: 0.25)) { hud = nil }
    }
}

extension View {
    /// 挂播放手势：长按加速 + （全屏时）左右半屏竖滑调亮度/音量
    func playerGestures(
        engine: PlaybackEngine,
        systemGestures: Bool,
        hud: Binding<PlayerHUDKind?>,
        hudValue: Binding<Double>
    ) -> some View {
        modifier(
            PlayerGestureModifier(
                engine: engine,
                systemGestures: systemGestures,
                hud: hud,
                hudValue: hudValue
            )
        )
    }
}
