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
                    .frame(height: 24)

                Text(item.title)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Theme.pink : Theme.ink.opacity(0.78))
            // 透明玻璃背后是封面/字幕这类高对比内容，一圈极淡的描边阴影
            // 就能把字从背景里"抠"出来，比加厚材质划算得多
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.22), radius: 2.5, y: 0.5)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if active {
                    selectionOval
                }
            }
            .contentShape(.rect)
        }
        // 点按同样浮出一圈更大的椭圆玻璃（spread 小一点，刚好包住整项）
        .buttonStyle(LiquidPressStyle(scale: 0.94, spread: 4))
    }

    /// 选中态：一块**包住图标和文字**的大椭圆玻璃（Apple TV 那种），
    /// 而不是只垫在图标下面的小方块。`glassEffectID` 让它在两项之间流动。
    ///
    /// tint 只给 0.10：再高就变成一块粉色的实心椭圆，玻璃的通透感没了。
    /// 品牌色交给图标和文字去承担，椭圆本身保持中性玻璃。
    private var selectionOval: some View {
        Capsule(style: .continuous)
            .glassEffect(
                .regular.tint(Theme.pink.opacity(0.10)).interactive(),
                in: .capsule
            )
            .liquidEdge(Capsule(style: .continuous), lineWidth: 1)
            .glassEffectID("tab-active", in: tabNamespace)
            .padding(.horizontal, 1)
    }
}
