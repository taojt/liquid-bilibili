import SwiftUI

/// 顶部二级分类 Tab。
///
/// 选中态的胶囊放在 GlassEffectContainer 里并用 glassEffectID 关联，
/// 切换时形状会在容器内平滑过渡，而不是简单淡入淡出。
///
/// 明暗适配的要点：
/// - 深色下玻璃底是黑，粉色 tint 稍微提亮就够；
/// - 浅色下玻璃底是白，同样的 tint 会被稀释成「脏粉」，文字也糊。
///   因此选中态改成**高饱和粉色渐变实底 + 白字**，不再依赖玻璃的透光；
///   未选中项不铺底，只压在一层极淡的「轨道」上，靠字重和颜色区分。
///   这样两套主题下对比度都是稳定的，不会因为背景变化而漂移。
struct SegmentTabs: View {
    let titles: [String]
    @Binding var selection: Int
    @Namespace private var segmentNamespace

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        button(index: index, title: title)
                    }
                }
                .padding(3)
                .background {
                    track
                }
                // 必须钉住固有宽度：横向 ScrollView 会把容器宽度提给内容，
                // HStack 里若干 Text 吸收掉多余空间后，轨道底会被撑到屏幕右侧，
                // 出现「直播」后面拖一截空胶囊的问题。
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// 轨道底：浅色下需要一点「凹槽感」把未选中项托住，
    /// 否则一排纯文字浮在浅色画布上会显得散。
    ///
    /// 浅色下只靠一层灰fill会显得像「脏色块」，所以叠两道描边：
    /// 内侧一道白色渐变高光（玻璃受光的边缘），外侧一道极细墨色勾边（界定轮廓）。
    /// 深色下反过来，高光弱一些，避免轨道发白发亮。
    private var track: some View {
        Capsule(style: .continuous)
            .fill(Theme.ink.opacity(colorScheme == .dark ? 0.10 : 0.06))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.10), .white.opacity(0.015)]
                                : [.white.opacity(0.85), .white.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.06), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func button(index: Int, title: String) -> some View {
        let active = selection == index
        Button {
            withAnimation(.snappy(duration: 0.26)) {
                selection = index
            }
        } label: {
            if active {
                activeLabel(title)
            } else {
                inactiveLabel(title)
            }
        }
        .buttonStyle(.plain)
    }

    private func activeLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: Theme.pink.opacity(0.45), radius: 4, y: 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.pink, Theme.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        // 顶部一道细高光，模拟玻璃边缘的反光
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: Theme.pink.opacity(0.35), radius: 6, y: 2)
            }
            .glassEffectID("segment-active", in: segmentNamespace)
    }

    private func inactiveLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Theme.inkDim)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
    }
}
