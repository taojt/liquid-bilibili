import SwiftUI

/// 统一的液态玻璃面板。所有自定义玻璃都应经由这里，
/// 便于集中控制 tint 与 interactive，避免散落的 glassEffect 造成合成开销。
///
/// 注意：`corner` 必须**同时**传给 `glassEffect(_:in:)`。
/// 只写 `.clipShape(.rect(cornerRadius:))` 是无效的——玻璃材质本身仍是
/// 系统的默认形状（近乎胶囊的超大圆角），裁切只能裁内容，
/// 于是最终视觉永远是「两头椭圆」，这也是之前设置卡片刻度压不下去的原因。
struct GlassPanel<Content: View>: View {
    var tint: Color?
    var interactive: Bool
    var corner: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        tint: Color? = nil,
        interactive: Bool = false,
        corner: CGFloat = Theme.innerRadius,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.interactive = interactive
        self.corner = corner
        self.content = content
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    var body: some View {
        styled
            .clipShape(shape)
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
    }
}

/// 顶部/底部的玻璃条，用于覆盖在内容之上
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}
