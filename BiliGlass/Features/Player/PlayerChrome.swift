import SwiftUI

/// 播放器控件。参照 iOS 系统播放器的排布：中间一颗大的播放/暂停，
/// 两侧是 ±10 秒的圆玻璃按钮，底部一条胶囊玻璃承载时间和进度。

// MARK: - 快进 / 回退

/// ±10 秒。图标用系统的 `gobackward.10` / `goforward.10`，
/// 数字画在箭头里，一眼就知道跳多少，不用额外写字。
struct PlayerSkipButton: View {
    let forward: Bool
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .buttonStyle(.iconPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(forward ? "快进 10 秒" : "后退 10 秒")
    }
}

// MARK: - 中央控制簇

/// 后退 10 秒 / 播放暂停 / 前进 10 秒。
///
/// 三颗按钮之间留得比较开（spacing 是全尺寸的一半）：点按外围会浮出椭圆玻璃，
/// 挨太近会连成一片。
struct PlayerCenterCluster: View {
    let isPlaying: Bool
    var playSize: CGFloat = 54
    var skipSize: CGFloat = 42
    let onToggle: () -> Void
    let onSkip: (Double) -> Void

    var body: some View {
        HStack(spacing: playSize * 0.42) {
            PlayerSkipButton(forward: false, size: skipSize) { onSkip(-10) }
            playButton
            PlayerSkipButton(forward: true, size: skipSize) { onSkip(10) }
        }
    }

    private var playButton: some View {
        Button(action: onToggle) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: playSize * 0.36, weight: .bold))
                .foregroundStyle(.white)
                // 播放/暂停图标视觉重心偏左，右移一点点才真的看着居中
                .offset(x: isPlaying ? 0 : playSize * 0.03)
                .frame(width: playSize, height: playSize)
        }
        .buttonStyle(LiquidPressStyle(scale: 0.92, spread: 6))
        .glassEffect(.regular.tint(Theme.pink.opacity(0.35)).interactive(), in: .circle)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }
}

// MARK: - 胶囊进度条

/// 底部那条胶囊玻璃：`[当前时间] [细进度轨] [-剩余时间]`。
///
/// 刻意不用 `Slider`：系统 slider 自带白色圆点把手和固定的高度与间距，
/// 想要截图里那种「一条细线 + 两端时间」的形态只能自己画。
struct PlayerProgressCapsule: View {
    let current: Double
    let duration: Double
    var compact: Bool = true
    /// 拖动过程中回调（用于外部显示预览时间），松手才真正 seek
    let onSeek: (Double) -> Void

    @State private var dragging = false
    @State private var dragValue: Double = 0

    private var barHeight: CGFloat { compact ? 3 : 4 }
    private var timeSize: CGFloat { compact ? 10 : 12 }
    private var timeWidth: CGFloat { compact ? 38 : 46 }

    private var value: Double { dragging ? dragValue : current }

    /// 不足 1 秒的剩余时长按 0 显示，避免出现 `-0:00`
    private var remaining: Int { Int(Swift.max(0, duration - value).rounded(.down)) }

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            Text(Int(value).clockText)
                .font(.system(size: timeSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: timeWidth, alignment: .leading)

            track

            // 右侧是**剩余**时间（截图里就是 -2:28），不是总时长
            Text("-" + remaining.clockText)
                .font(.system(size: timeSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: timeWidth, alignment: .trailing)
        }
        .padding(.horizontal, compact ? 13 : 18)
        .padding(.vertical, compact ? 7 : 11)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeOut(duration: 0.18), value: dragging)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = duration > 0 ? min(1, Swift.max(0, value / duration)) : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(dragging ? 0.30 : 0.22))
                    .frame(height: barHeight)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.95), Theme.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * ratio, height: barHeight)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            // 轨道只有几像素高，直接给它加手势几乎点不中，撑一个 24pt 的命中区
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard duration > 0 else { return }
                        dragging = true
                        let ratio = min(1, Swift.max(0, gesture.location.x / width))
                        dragValue = ratio * duration
                    }
                    .onEnded { _ in
                        guard duration > 0 else { return }
                        onSeek(dragValue)
                        dragging = false
                    }
            )
        }
        .frame(height: barHeight + 18)
    }
}

// MARK: - 手势 HUD

/// 竖滑调亮度/音量、长按加速时的反馈气泡。
enum PlayerHUDKind: Equatable {
    case brightness
    case volume
    case speed(Float)

    var icon: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.3.fill"
        case .speed: return "forward.fill"
        }
    }

    var title: String {
        switch self {
        case .brightness: return "亮度"
        case .volume: return "音量"
        case .speed: return "倍速播放中"
        }
    }
}

/// 亮度/音量用一个竖着的圆角玻璃泡泡显示图标 + 百分比；
/// 倍速不需要数值，是横向的小胶囊。
struct PlayerHUDBubble: View {
    let kind: PlayerHUDKind
    let value: Double

    var body: some View {
        switch kind {
        case .brightness, .volume:
            VStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                // 竖向填充条，从下往上涨
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white)
                        .frame(height: 68 * min(max(value, 0), 1))
                }
                .frame(width: 5, height: 68)

                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

        case .speed(let rate):
            HStack(spacing: 7) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(String(format: "%gx", rate))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("倍速播放中")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
        }
    }
}
