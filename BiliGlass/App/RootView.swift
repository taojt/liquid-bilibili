import SwiftUI

struct RootView: View {
    @State private var selection = 0

    /// 四个 Tab 各自持有一条显式导航路径。
    ///
    /// 用显式 `NavigationPath`（普通 `@State`，不落盘）而不是让 `NavigationStack`
    /// 自己管理，是为了避免 iOS 的场景状态恢复把上次停留的详情页/搜索页在冷启动时
    /// 重新推上来——那样每次打开 App 都进不到首页，调试和真机验证都很别扭。
    @State private var homePath = NavigationPath()
    @State private var dynamicPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var profilePath = NavigationPath()

    /// 已经挂载过的 Tab。
    ///
    /// 不用系统 `TabView` 之后要自己决定「谁还活着」：切走的 Tab 不能销毁，
    /// 否则回来时列表、滚动位置、分页进度全丢；但四个都常驻又会让冷启动
    /// 同时打四组接口。折中是**首次进入才挂载、之后一直保留**。
    @State private var mounted: Set<Int> = [0]

    /// 当前 Tab 是否被 push 的页面盖住（详情页 / 搜索页 / 主页等）
    private var tabBarCovered: Bool {
        FloatingTabGate.shared.isCovered(selection)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tab(index: 0, path: $homePath) { HomeView() }
            tab(index: 1, path: $dynamicPath) { DynamicView() }
            tab(index: 2, path: $historyPath) { HistoryView() }
            tab(index: 3, path: $profilePath) { ProfileView() }

            // 被 push 的页面（详情页 / 全屏播放 / 搜索 / 各主页）自己会登记，
            // 登记期间把悬浮栏收起来：玻璃胶囊再不透明也会压住页面底部内容。
            if !tabBarCovered {
                FloatingTabBar(selection: $selection)
                    // zIndex 要压过激活 Tab（它的 zIndex 是 1），否则整条栏
                    // 会被 Tab 内容盖在下面，屏幕上直接看不见
                    .zIndex(10)
                    .transition(.opacity.combined(with: .offset(y: 24)))
            }
        }
        .environment(\.rootTabIndex, selection)
        // 兜底底色。原先根部的系统 `TabView` 会在屏幕最底部留一条
        // 「已隐藏但仍在」的 TabBar 背板，深色外观下它仍按浅色渲染，
        // 屏幕上就是一条白边；换成自绘切换后没有这层了，再铺一层画布色
        // 保证任何缝隙都不会漏出窗口默认的白底。
        .background(Theme.canvas.ignoresSafeArea())
        .animation(.snappy(duration: 0.24), value: tabBarCovered)
        .preferredColorScheme(AppSettings.shared.colorScheme)
        .tint(Theme.pink)
        .onChange(of: selection) { _, new in
            mounted.insert(new)
        }
        .onAppear {
            AuthService.shared.restore()
            if let tab = DebugEntry.tab {
                selection = tab
                mounted.insert(tab)
            }
        }
        .task {
            // 设备指纹缺失时很多接口会被风控降级，启动补一次
            await BiliAPI.shared.ensureFingerprint()
        }
    }

    /// 单个 Tab 的容器。
    ///
    /// 未选中的 Tab 保留在层级里（保住状态），靠 `opacity` + `allowsHitTesting`
    /// 藏起来；`zIndex` 要跟着切，否则隐藏的那几个仍会把点击/焦点抢走。
    @ViewBuilder
    private func tab<Content: View>(
        index: Int,
        path: Binding<NavigationPath>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if mounted.contains(index) {
            let active = selection == index
            NavigationStack(path: path) {
                content()
            }
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 1 : 0)
        }
    }
}
