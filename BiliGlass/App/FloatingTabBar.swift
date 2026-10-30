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
            .glassEffect(.regular, in: barShape)
        }
        .liquidEdge(barShape, lineWidth: 1.1, elevated: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
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
                    .foregroundStyle(active ? .white : Theme.inkDim.opacity(0.85))
                    .frame(width: 34, height: 27)
                    .background {
                        if active {
                            tile
                        }
                    }

                Text(item.title)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Theme.pink : Theme.inkDim.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 选中项底下的小玻璃砖。粉 tint 只压到 0.32——
    /// 再高会把背后的瀑布流颜色完全盖掉，玻璃就变成色块了
    private var tile: some View {
        tileShape
            .fill(Theme.pink.opacity(0.16))
            .glassEffect(
                .regular.tint(Theme.pink.opacity(0.32)).interactive(),
                in: tileShape
            )
            .liquidEdge(tileShape, lineWidth: 0.8)
            .glassEffectID("tab-active", in: tabNamespace)
    }
}
