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

// MARK: - 液态点按

/// 点按时在控件**外围**浮出一圈更大的椭圆玻璃。
///
/// 参照 Apple TV 底栏选中态：不是给按钮本身镀一层，而是一块比内容更大的
/// 椭圆玻璃托在下面，边缘有一圈受光高光。所以这里用 `.padding(-spread)`
/// 把椭圆往外扩，而不是贴着按钮边界画。
///
/// 不用真实 `glassEffect` 的原因：按压是高频、瞬态的交互，每次按压都新建
/// 销毁一层玻璃材质，首次出现会有明显掉帧，而且材质出现/消失是硬切。
/// 这里用「半透明填充 + 受光描边 + 柔光晕」画出来，靠动画驱动，
/// 观感和玻璃一致但代价接近于零。
/// 点按椭圆的轮廓。
///
/// 一律用胶囊是不行的：底栏、圆形图标按钮是矮胖形状，胶囊正合适；
/// 但封面卡片是近乎方形的矩形，胶囊的两端半圆会在卡片外圈糊出一圈
/// 白光大圆框，横向还会溢到相邻卡片上。所以卡片类改成跟随卡片圆角。
enum PressShape {
    case capsule
    case rounded(CGFloat)
}

struct LiquidPressStyle: ButtonStyle {
    /// 按下时内缩比例。控制类按钮别缩太多，卡片可以多一点
    var scale: CGFloat = 0.96
    /// 椭圆相对控件外扩多少（负 padding）
    var spread: CGFloat = 10
    /// 光晕颜色，默认无
    var glow: Color?
    /// 椭圆轮廓
    var shape: PressShape = .capsule

    func makeBody(configuration: Configuration) -> some View {
        // `-debugPressPreview YES` 时全部常显，真机没法脚本化按压，靠这个核对椭圆尺寸
        let pressed = configuration.isPressed || DebugEntry.pressPreview
        return configuration.label
            .scaleEffect(pressed ? scale : 1)
            .background {
                LiquidPressOval(isPressed: pressed, spread: spread, glow: glow, shape: shape)
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.62), value: pressed)
    }
}

private struct LiquidPressOval: View {
    let isPressed: Bool
    let spread: CGFloat
    let glow: Color?
    let shape: PressShape

    @Environment(\.colorScheme) private var scheme

    /// 擦除成 AnyShape 是为了让 fill / stroke 用同一份轮廓。
    /// 按压是瞬态渲染，这点类型擦除的代价可以忽略。
    private var outline: AnyShape {
        switch shape {
        case .capsule:
            AnyShape(Capsule(style: .continuous))
        case .rounded(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    var body: some View {
        ZStack {
            if let glow {
                outline
                    .fill(glow.opacity(scheme == .dark ? 0.45 : 0.30))
                    .blur(radius: 16)
                    .padding(-spread - 4)
            }

            outline
                .fill(fill)
                .overlay {
                    // 顶部受光 / 底部反光，玻璃的立体感全靠这道描边
                    outline.stroke(
                        LinearGradient(
                            stops: scheme == .dark
                                ? [
                                    .init(color: .white.opacity(0.62), location: 0),
                                    .init(color: .white.opacity(0.10), location: 0.5),
                                    .init(color: .white.opacity(0.26), location: 1)
                                ]
                                : [
                                    .init(color: .white.opacity(0.98), location: 0),
                                    .init(color: .white.opacity(0.45), location: 0.5),
                                    .init(color: .black.opacity(0.06), location: 1)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                // 浅色下白底和页面底色贴合，只能靠一圈软影把轮廓托出来
                .shadow(
                    color: scheme == .dark ? .black.opacity(0.28) : .black.opacity(0.12),
                    radius: 9,
                    y: 3
                )
                .padding(-spread)
        }
        .scaleEffect(isPressed ? 1 : 0.82)
        .opacity(isPressed ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.30, dampingFraction: 0.62), value: isPressed)
    }

    /// 深色下靠提亮（白 0.15），浅色下靠一层薄白 + 外投影界定轮廓。
    /// 浅色不要再往上加：到 0.6 左右就成了一块实心白片，
    /// 压在深色视频上尤其突兀，玻璃的「透」完全没了。
    private var fill: Color {
        scheme == .dark ? .white.opacity(0.15) : .white.opacity(0.45)
    }
}

extension ButtonStyle where Self == LiquidPressStyle {
    /// 全 App 通用的点按反馈：外扩一圈椭圆玻璃
    static var liquidPress: LiquidPressStyle { LiquidPressStyle() }

    /// 封面卡片 / 列表行：轮廓跟着卡片圆角走，外扩收窄，
    /// 免得压到相邻卡片上
    static var cardPress: LiquidPressStyle {
        LiquidPressStyle(scale: 0.975, spread: 6, shape: .rounded(Theme.coverRadius + 3))
    }

    /// 图标按钮：比默认更收一点，避免椭圆盖住相邻的图标
    static var iconPress: LiquidPressStyle {
        LiquidPressStyle(scale: 0.93, spread: 4)
    }

    /// 矮扁的胶囊标签（二级 Tab 这类）：纵向再收，否则会压到下一条内容
    static var chipPress: LiquidPressStyle {
        LiquidPressStyle(scale: 0.95, spread: 6)
    }
}

// MARK: - 玻璃面板

/// 统一的液态玻璃面板。所有自定义玻璃都应经由这里，
/// 便于集中控制 tint 与 interactive，避免散落的 glassEffect 造成合成开销。
///
/// 注意：`corner` 必须**同时**传给 `glassSurface(_:in:)`。
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
                base.glassSurface(.regular.tint(tint).interactive(), in: shape)
            } else {
                base.glassSurface(.regular.tint(tint), in: shape)
            }
        } else {
            if interactive {
                base.glassSurface(.regular.interactive(), in: shape)
            } else {
                base.glassSurface(.regular, in: shape)
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
                .glassSurface(
                    tint.map { GlassSpec.regular.tint($0).interactive() } ?? .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.liquidPress)
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
            .glassSurface(.regular, in: shape)
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
        .glassSurface(
            (tint.map { GlassSpec.regular.tint($0.opacity(0.4)) } ?? .regular).interactive(),
            in: .capsule
        )
        .liquidEdge(Capsule(style: .continuous), lineWidth: 0.7)
    }
}
