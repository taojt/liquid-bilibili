import SwiftUI

// MARK: - 光学边缘

/// 给玻璃表面补一层「光学边缘」。
///
/// `glassEffect` 本身负责材质与折射，但它**只做背景采样**，边缘对比度很低：
/// 深色背景下玻璃和底色几乎同亮度，糊成一团；浅色背景下又像一坨白色磨砂。
/// iOS 27 系统控件之所以有"液态"感，靠的是边缘那道受光高光 + 底边的暗边，
/// 加上一层往下打的柔和投影把玻璃"托"离内容。
///
/// 这里按明暗两套给不同的描边梯度：
/// - 深色：左上白 0.5 → 右下白 0.12，模拟顶光；
/// - 浅色：左上纯白 → 右下墨色 0.06，浅色界面里靠暗边界定轮廓。
struct LiquidEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    var lineWidth: CGFloat = 1
    /// 是否抬起（带外投影）。小的内嵌控件不需要，整条悬浮栏需要
    var elevated: Bool = false

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: scheme == .dark
                                ? [
                                    .init(color: .white.opacity(0.52), location: 0),
                                    .init(color: .white.opacity(0.10), location: 0.45),
                                    .init(color: .white.opacity(0.16), location: 1)
                                ]
                                : [
                                    .init(color: .white.opacity(0.98), location: 0),
                                    .init(color: .white.opacity(0.35), location: 0.5),
                                    .init(color: .black.opacity(0.07), location: 1)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: lineWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(elevated ? (scheme == .dark ? 0.55 : 0.14) : 0),
                radius: elevated ? 20 : 0,
                y: elevated ? 10 : 0
            )
    }
}

extension View {
    /// 玻璃/卡片表面统一走这里，保证全 App 的"受光方向"一致
    func liquidEdge<S: InsettableShape>(
        _ shape: S,
        lineWidth: CGFloat = 1,
        elevated: Bool = false
    ) -> some View {
        modifier(LiquidEdge(shape: shape, lineWidth: lineWidth, elevated: elevated))
    }
}

// MARK: - 玻璃面板

/// 统一的液态玻璃面板。所有自定义玻璃都应经由这里，
/// 便于集中控制 tint 与 interactive，避免散落的 glassEffect 造成合成开销。
///
/// 注意：`corner` 必须**同时**传给 `glassEffect(_:in:)`。
/// 只写 `.clipShape(.rect(cornerRadius:))` 是无效的——玻璃材质本身仍是
/// 系统的默认形状（近乎胶囊的超大圆角），裁切只能裁内容，
/// 于是最终视觉永远是「两头椭圆」。
struct GlassPanel<Content: View>: View {
    var tint: Color?
    var interactive: Bool
    var corner: CGFloat
    var elevated: Bool
    @ViewBuilder var content: () -> Content

    init(
        tint: Color? = nil,
        interactive: Bool = false,
        corner: CGFloat = Theme.innerRadius,
        elevated: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.interactive = interactive
        self.corner = corner
        self.elevated = elevated
        self.content = content
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    var body: some View {
        styled
            .clipShape(shape)
            .liquidEdge(shape, elevated: elevated)
    }

    @ViewBuilder
    private var styled: some View {
        let base = content()
        if let tint {
            if interactive {
                base.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                base.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            if interactive {
                base.glassEffect(.regular.interactive(), in: shape)
            } else {
                base.glassEffect(.regular, in: shape)
            }
        }
    }
}

/// 悬浮圆形图标按钮，玻璃 + 触摸反馈
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 40
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .glassEffect(
                    tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .liquidEdge(Circle(), lineWidth: 0.9)
    }
}

/// 顶部/底部的玻璃条，用于覆盖在内容之上
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: shape)
            .liquidEdge(shape, elevated: true)
    }
}

// MARK: - 玻璃胶囊（角标 / 标签）

/// 压在封面上的小玻璃胶囊（时长、播放量这类）。
///
/// 直接 `glassEffect` 在缩略图上会太"透明"，文字读不清，所以额外压一层
/// 深色渐变底 + 顶部高光：既有玻璃的通透，又保证 9pt 小字可读。
struct GlassTag: View {
    var icon: String?
    var text: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(.black.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .fill((tint ?? Theme.pink).opacity(tint == nil ? 0 : 0.55))
                }
        }
        .glassEffect(
            (tint.map { Glass.regular.tint($0.opacity(0.4)) } ?? .regular).interactive(),
            in: .capsule
        )
        .liquidEdge(Capsule(style: .continuous), lineWidth: 0.7)
    }
}
