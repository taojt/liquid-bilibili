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

    /// 栏体玻璃的 tint。
    ///
    /// iOS 26 的 Liquid Glass 是「透光 + 边缘折射」，**不负责把背后的内容糊掉**：
    /// 背后是高对比封面时，缩略图上的字会清晰地透上来和标签打架。
    /// 所以下面额外垫了一层 `.ultraThinMaterial` 负责真正的背景模糊，
    /// 玻璃负责透光和边缘——两者叠起来才是系统 Dock 那种磨砂玻璃。
    private var barTint: Color {
        scheme == .dark ? .black.opacity(0.22) : .white.opacity(0.28)
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
            .background {
                barShape.fill(.ultraThinMaterial)
            }
            .glassEffect(.regular.tint(barTint), in: barShape)
        }
        .liquidEdge(barShape, lineWidth: 1.1, elevated: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
                    .foregroundStyle(active ? .white : Theme.inkDim)
                    .frame(width: 34, height: 27)
                    .background {
                        if active {
                            tile
                        }
                    }

                Text(item.title)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                    // InkDim 自带 0.62 透明度，别再叠一层，否则浅色主题下
                    // 未选中项淡到几乎看不见
                    .foregroundStyle(active ? Theme.pink : Theme.inkDim)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 选中项底下的小玻璃砖。
    ///
    /// 只留玻璃、不再垫一层粉色实底：垫了实底之后玻璃被完全挡住，
    /// 砖就退化成一个粉色圆角方块，玩具感很重。纯玻璃 + 0.35 的粉 tint
    /// 才是"一块被染上品牌色的玻璃"——能透出背后的瀑布流，边缘还带受光。
    private var tile: some View {
        tileShape
            .glassEffect(
                .regular.tint(Theme.pink.opacity(0.35)).interactive(),
                in: tileShape
            )
            .liquidEdge(tileShape, lineWidth: 0.8)
            .glassEffectID("tab-active", in: tabNamespace)
    }
}
