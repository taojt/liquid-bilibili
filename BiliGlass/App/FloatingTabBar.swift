import SwiftUI

/// 悬浮玻璃 TabBar。
///
/// 不用系统 `TabView` 自带的底栏：那条底栏是一整块不透明背板，
/// 会把瀑布流硬切掉一条。这里改成一条独立的玻璃胶囊，浮在内容之上，
/// 内容可以继续在它下面滚动、透过玻璃露出来。
///
/// 造型参考 Apple TV：整条近乎满宽的玻璃条，图标在上、文字在下，
/// 选中项的图标落在一块独立的小玻璃砖上——`GlassEffectContainer` +
/// `glassEffectID` 让这块砖在切换时**在两点之间流动**，途中会和
/// 底下的玻璃条短暂融合，这就是液态玻璃最直观的那一下。
///
/// 透明度的取舍：`glassEffect` 只做透光和边缘折射，**不做背景模糊**，
/// 背后是高对比封面时缩略图上的字会清晰透上来和标签打架。之前的做法是
/// 垫一层不透明的 `.ultraThinMaterial` 把内容糊掉——结果栏变成一块白板，
/// 完全失去玻璃质感。现在改成：只留很薄的一层模糊（`ultraThinMaterial`
/// 单独用就已经是最薄的一档，再叠 `tint` 就实了），tint 压到极低，
/// 靠**底部渐隐只做轻压**（见 RootView）让内容带色彩地透上来。
struct FloatingTabBar: View {
    @Binding var selection: Int

    private struct Item {
        let title: String
        let icon: String
        let activeIcon: String
    }

    private let items: [Item] = [
        Item(title: "首页", icon: "play.rectangle", activeIcon: "play.rectangle.fill"),
        Item(title: "动态", icon: "bolt.horizontal", activeIcon: "bolt.horizontal.fill"),
        Item(title: "历史", icon: "clock.arrow.circlepath", activeIcon: "clock.arrow.circlepath"),
        Item(title: "我的", icon: "person.crop.circle", activeIcon: "person.crop.circle.fill")
    ]

    @Namespace private var tabNamespace
    @Environment(\.colorScheme) private var scheme

    /// 栏体玻璃不再额外 tint（`.regular` 自带的乳白已经够把标签托起来），
    /// 保留这个开关只为以后微调
    private var barTint: Color {
        scheme == .dark ? .black.opacity(0.10) : .white.opacity(0.10)
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    button(index: index)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(height: 62)
            // 就是系统原样的 `.regular` 玻璃，不叠材质、不加 tint。
            //
            // 走过两条弯路，记下来免得再踩：
            // 1. 底下垫 `.ultraThinMaterial` —— 它自带六成白底，叠完栏就是一块白板，
            //    内容一点透不过来；
            // 2. `.clear` 变体 —— 它是给"压在视频/深色媒体上"设计的，浅色界面里
            //    会渲染成烟熏黑，和浅色主题直接打架。
            // `.regular` 本身就是「透光 + 边缘折射 + 一层很薄的乳白」，最贴近要的效果；
            // 标签可读性靠下面那圈描边阴影解决，比加厚材质划算。
            .glassEffect(.regular, in: barShape)
        }
        .liquidEdge(barShape, lineWidth: 1.1, elevated: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        // 切换 Tab 时给一次轻微触感，配合下面的液态点按
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func button(index: Int) -> some View {
        let active = selection == index
        let item = items[index]
        return Button {
            guard selection != index else { return }
            withAnimation(.snappy(duration: 0.28)) {
                selection = index
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? item.activeIcon : item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    // 选中项的图标压在粉玻璃砖上，必须用白色，否则同色系糊成一团
                    .foregroundStyle(active ? .white : Theme.ink)
                    .frame(width: 34, height: 27)
                    .background {
                        if active {
                            tile
                        }
                    }

                Text(item.title)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Theme.pink : Theme.ink.opacity(0.78))
            }
            // 透明玻璃背后是封面/字幕这类高对比内容，一圈极淡的描边阴影
            // 就能把字从背景里"抠"出来，比加厚材质划算得多
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.22), radius: 2.5, y: 0.5)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(LiquidTabStyle())
    }

    /// 选中项底下的小玻璃砖。
    ///
    /// 纯玻璃 + 0.24 的粉 tint：垫实底会把玻璃完全挡住，退化成粉色圆角方块；
    /// tint 再高也一样——砖必须是「染上品牌色的玻璃」，能透出背后的瀑布流。
    private var tile: some View {
        tileShape
            .glassEffect(
                .regular.tint(Theme.pink.opacity(0.24)).interactive(),
                in: tileShape
            )
            .liquidEdge(tileShape, lineWidth: 0.8)
            .glassEffectID("tab-active", in: tabNamespace)
    }
}

/// 液态点按。
///
/// 按下时整项轻微内缩，同时从图标位置扩开一团柔光——缩是"按下去"，
/// 光是"玻璃被挤压后透出来的亮"，两件事叠在一起才有液态感。
/// 用 `ButtonStyle` 而不是 `onLongPressGesture`：后者的 pressing 状态
/// 拿不到真实的按下/抬起时机，动画会断。
private struct LiquidTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 0.90 而不是更低：整项连文字一起缩，缩太多会显得"塌"
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .background {
                // 对齐图标中心：整项高约 42，图标中心在 y≈13.5，故上移 7.5
                Circle()
                    .fill(Theme.pink.opacity(0.50))
                    .frame(width: 40, height: 40)
                    .blur(radius: 13)
                    .scaleEffect(configuration.isPressed ? 1.28 : 0.5)
                    .opacity(configuration.isPressed ? 0.75 : 0)
                    .offset(y: -7.5)
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.58), value: configuration.isPressed)
    }
}
