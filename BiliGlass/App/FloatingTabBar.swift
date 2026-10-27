import SwiftUI

/// 悬浮玻璃 TabBar。
///
/// 不用系统 `TabView` 自带的底栏：那条底栏是一整块不透明背板，
/// 会把瀑布流硬切掉一条。这里改成一条独立的玻璃胶囊，浮在内容之上，
/// 内容可以继续在它下面滚动、透过玻璃露出来。
///
/// 选中高亮用 `GlassEffectContainer` + `glassEffectID` 关联，
/// 切换时高亮块会在两个位置之间流体过渡，而不是原地淡入淡出。
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

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(items.indices, id: \.self) { index in
                    button(index: index)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func button(index: Int) -> some View {
        let active = selection == index
        let item = items[index]
        return Button {
            guard selection != index else { return }
            withAnimation(.snappy(duration: 0.26)) {
                selection = index
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? item.activeIcon : item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 17)
                Text(item.title)
                    .font(.system(size: 9, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Theme.pink : Theme.inkDim)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.pink.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.pink.opacity(0.28), lineWidth: 0.8)
                        }
                        .glassEffectID("tab-active", in: tabNamespace)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
