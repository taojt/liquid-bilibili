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
                // 玻璃必须直接作用在容器上，**不能**放进 `.background {}`：
                // glassEffect 是独立合成的材质层，挂成背景时会盖在前景文字上，
                // 选择项和未选择项的文字会一起被糊成一层灰影。
                .glassEffect(.regular, in: .capsule)
                .liquidEdge(Capsule(style: .continuous), lineWidth: 0.9)
                // 必须钉住固有宽度：横向 ScrollView 会把容器宽度提给内容，
                // HStack 里若干 Text 吸收掉多余空间后，轨道底会被撑到屏幕右侧，
                // 出现「直播」后面拖一截空胶囊的问题。
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
        .buttonStyle(.chipPress)
        // 选中态交给无障碍层：VoiceOver 会念「已选中」，UI 测试也能靠 isSelected 断言，
        // 否则只能去比背景色
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// 选中态：高饱和粉紫渐变实底 + 白字。
    ///
    /// 这里刻意**不**再叠一层 glassEffect：玻璃 tint 在浅色主题下会被背景稀释成
    /// 「脏粉」，白字直接糊掉；实色渐变能保证两套主题下对比度稳定。
    /// "玻璃感"交给轨道层和那一圈受光描边来提供。
    private func activeLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
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
                        // 顶部一道细高光 + 底部一道反光，模拟玻璃棒受光
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.55),
                                        .white.opacity(0.06),
                                        .white.opacity(0.22)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(color: Theme.pink.opacity(0.30), radius: 8, y: 3)
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
