import SwiftUI

/// 一键三连的动效。
///
/// 以点赞按钮为原点向上扇形飞出三枚图标（赞 / 币 / 星），
/// 同时扩散一圈光环、浮出「一键三连」字样，1 秒后自动消失。
///
/// `tick` 每 +1 重播一次：内部用 `.id(tick)` 重建子视图，
/// 比手动复位 `@State` 更不容易漏掉连击。
struct TripleLinkBurst: View {
    let tick: Int
    /// 动画原点（相对父视图左上角），默认对齐操作栏第一个按钮的中心
    var origin: CGPoint = CGPoint(x: 44, y: 24)
    /// 调试用：给定 0~1 的进度则**不播动画**，直接定格在该帧。
    /// 截图脚本很难刚好命中 1 秒的动画窗口，定格可以把中间态固化成静态图。
    var frozenProgress: CGFloat? = nil

    var body: some View {
        if tick > 0 {
            Burst(frozen: frozenProgress)
                .id(tick)
                // 必须给一个**确定的非零尺寸**：`frame(width: 0, height: 0)` 会把
                // 里面的 Text 压成 0 宽（图标有固定尺寸反而看不出问题），
                // 「一键三连」那个胶囊就一直不显示。
                .frame(width: side, height: side)
                .offset(x: origin.x - side / 2, y: origin.y - side / 2)
                .allowsHitTesting(false)
        }
    }

    private let side: CGFloat = 140
}

private struct Burst: View {
    var frozen: CGFloat?
    @State private var progress: CGFloat = 0

    private struct Item {
        let icon: String
        let color: Color
        /// 起飞角度（度），-90 为正上方
        let angle: Double
    }

    private let items: [Item] = [
        Item(icon: "hand.thumbsup.fill", color: Theme.pink, angle: -152),
        Item(icon: "bitcoinsign.circle.fill", color: Theme.purple, angle: -90),
        Item(icon: "star.fill", color: Theme.blue, angle: -28)
    ]

    var body: some View {
        ZStack {
            ring
            icons
            caption
        }
        .onAppear {
            if let frozen {
                progress = frozen
                return
            }
            withAnimation(.easeOut(duration: 1.0)) {
                progress = 1
            }
        }
    }

    /// 一圈向外扩散并淡出的光环
    private var ring: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Theme.pink.opacity(0.7), Theme.purple.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 2
            )
            .frame(width: 26, height: 26)
            .scaleEffect(0.5 + progress * 2.4)
            .opacity(Double(1 - progress))
    }

    private var icons: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            let rad = item.angle * .pi / 180
            // 给一个初始半径，让三枚图标一开始就从按钮边缘起飞，
            // 而不是先叠在按钮中心再慢慢分开——叠在一起的那几帧很糊
            let dist = 16 + 46 * progress
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(item.color)
                .shadow(color: item.color.opacity(0.55), radius: 6)
                .offset(
                    x: CGFloat(cos(rad)) * dist,
                    y: CGFloat(sin(rad)) * dist
                )
                .scaleEffect(1 + 0.45 * progress)
                // 前 15% 淡入，之后淡出，避免「一开始就出现」的突兀感
                .opacity(progress < 0.15 ? Double(progress / 0.15) : Double(1 - (progress - 0.15) / 0.85))
        }
    }

    private var caption: some View {
        Text("一键三连")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.pink, Theme.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: Theme.pink.opacity(0.45), radius: 8, y: 2)
            .fixedSize()
            .offset(y: -20 - 4 * progress)
            .scaleEffect(0.7 + 0.3 * min(1, progress * 3))
            .opacity(progress < 0.12 ? Double(progress / 0.12) : Double(1 - (progress - 0.55) / 0.45))
    }
}
