import SwiftUI
import UIKit

// MARK: - 玻璃兼容层
//
// 这个 App 原本把部署目标定在 iOS 26.2，直接吃系统的 Liquid Glass。
// 现在要装到 iPadOS 17 的真机 iPad 上，部署目标降到 17.0，
// 于是所有 iOS 26 专属 API 都必须有降级路径。
//
// 收敛策略：**调用点只写语义**（`glassSurface(.regular.tint(x).interactive(), in: .capsule)`），
// 由本文件决定「系统玻璃」还是「自绘近似」。这样 73 处玻璃调用点
// 在 iOS 26 与 iOS 17 上共用一套代码，不会出现两套实现各改一半。
//
// 自绘近似不是"阉割版"：`glassEffect` 的核心观感是
// 「毛玻璃材质 + 顶光高光 + 轻微提亮」，这三样用 `.ultraThinMaterial`
// + 渐变填充就能还原八九成；差的只是实时折射——而本 App 的玻璃下方
// 基本都是纯色画布 + 极光色斑，折射差异肉眼几乎分辨不出。

// MARK: 材质语义

/// 玻璃材质的语义描述，替代 iOS 26 的 `Glass` 类型。
///
/// 之所以不直接沿用 `Glass`：它是 iOS 26 才有的类型，在部署目标 17 下
/// 连类型名都写不出来。这里只保留真正影响观感的三件事——
/// 底材质、tint、是否 interactive。
struct GlassSpec {
    enum Base {
        /// 薄乳白，系统 `Glass.regular`
        case regular
        /// 更透，系统 `Glass.clear`
        case clear
    }

    var base: Base = .regular
    var tintColor: Color?
    /// interactive 在 iOS 26 上让玻璃跟着触摸形变；
    /// 旧系统没有这个能力，由 LiquidPressStyle 的按下反馈代偿
    var interactivePress = false

    static var regular: GlassSpec { GlassSpec() }
    static var clear: GlassSpec { GlassSpec(base: .clear) }

    func tint(_ color: Color) -> GlassSpec {
        var copy = self
        copy.tintColor = color
        return copy
    }

    func interactive() -> GlassSpec {
        var copy = self
        copy.interactivePress = true
        return copy
    }
}

extension View {
    /// 铺一层液态玻璃。
    ///
    /// iOS 26+ 走系统 `glassEffect`；旧系统退到 `LegacyGlass` 的自绘近似。
    /// `shape` 必须同时参与绘制，不能只靠外层 `clipShape`——
    /// 系统玻璃的形状由这里决定，裁切只裁内容。
    @ViewBuilder
    func glassSurface<S: Shape>(_ spec: GlassSpec = .regular, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(systemGlass(spec), in: shape)
        } else {
            background { LegacyGlass(spec: spec, shape: shape) }
        }
    }
}

/// 把语义描述翻译成系统 `Glass`
@available(iOS 26.0, *)
private func systemGlass(_ spec: GlassSpec) -> Glass {
    var glass: Glass = spec.base == .clear ? .clear : .regular
    if let tint = spec.tintColor { glass = glass.tint(tint) }
    if spec.interactivePress { glass = glass.interactive() }
    return glass
}

/// 旧系统的玻璃近似：材质 + tint + 顶光渐变
private struct LegacyGlass<S: Shape>: View {
    let spec: GlassSpec
    let shape: S

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // `.regular` 是薄乳白；旧系统没有 tint 版本，只能 material + 色层叠
            shape.fill(spec.base == .clear ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))

            if let tint = spec.tintColor {
                shape.fill(tint.opacity(scheme == .dark ? 0.52 : 0.40))
            }

            // 顶光。平面材质没有折射，全靠这道渐变读出「有厚度」
            shape.fill(
                LinearGradient(
                    colors: scheme == .dark
                        ? [.white.opacity(0.15), .white.opacity(0.02)]
                        : [.white.opacity(0.32), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 玻璃融合

/// 让相邻玻璃彼此「吸附融合」的容器（iOS 26 `GlassEffectContainer`）。
///
/// 旧系统没有融合能力，直接透传内容：视觉上退化成各自独立的玻璃，
/// 观感差别只在两个玻璃靠得很近时的边缘粘连，实际看不出来。
struct GlassFusion<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// 给玻璃元素一个身份，让它在两个位置之间「流动」（iOS 26 `glassEffectID`）。
    ///
    /// 旧系统借 `matchedGeometryEffect` 达成同样的位移补间——
    /// 玻璃不会真的拉丝融合，但椭圆从上一项滑到下一项的动感是一致的。
    @ViewBuilder
    func glassFusionID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

// MARK: - 玻璃按钮

/// 替代系统的 `.buttonStyle(.glass)` / `.glassProminent`。
///
/// 这两个是 iOS 26 才有的样式。因为要让 iPad(iOS 17) 和 iPhone(iOS 26)
/// 外观一致，这里**统一自绘**，不再按系统版本分叉——
/// 系统的玻璃按钮样式各版本会微调，自绘反而更稳定。
///
/// 内边距由样式统一提供，调用点不要再自己加 `.padding`。
struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 24 : 15)
            .padding(.vertical, prominent ? 13 : 8)
            .background {
                if prominent {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.pink, Theme.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .liquidEdge(Capsule(style: .continuous), lineWidth: 0.8)
                } else {
                    Color.clear
                        .glassSurface(.regular.interactive(), in: Capsule(style: .continuous))
                }
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    /// 玻璃胶囊按钮（对应系统 `.glass`）
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }

    /// 品牌色实心胶囊按钮（对应系统 `.glassProminent`）
    static var liquidGlassProminent: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(prominent: true)
    }
}

// MARK: - 滚动相关

extension View {
    /// 滚动内容偏移（含顶部安全内边距）变化回调。
    ///
    /// iOS 18+ 用系统的 `onScrollGeometryChange`；旧系统退到 KVO 观察
    /// 底层 `UIScrollView.contentOffset`——比 `GeometryReader + PreferenceKey`
    /// 便宜得多，后者每次滚动都要重排一遍，长列表上很明显。
    @ViewBuilder
    func scrollOffsetChange(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                onChange(offset)
            }
        } else {
            background { ScrollOffsetProbe(onChange: onChange) }
        }
    }

    /// 顶部硬边缘（导航栏下压一层实色）。iOS 26 起才有可配置的 API，
    /// 旧系统用系统默认行为即可。
    @ViewBuilder
    func hardTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

/// 从自身往上找 `UIScrollView` 并观察它的 contentOffset
private struct ScrollOffsetProbe: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, observation == nil,
                  let scrollView = enclosingScrollView()
            else { return }

            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                let offset = sv.contentOffset.y + sv.adjustedContentInset.top
                // KVO 回调可能落在任意线程，SwiftUI 的状态更新必须在主线程
                DispatchQueue.main.async { self?.onChange?(offset) }
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var node: UIView? = superview
            while let current = node {
                if let scrollView = current as? UIScrollView { return scrollView }
                node = current.superview
            }
            return nil
        }
    }
}
