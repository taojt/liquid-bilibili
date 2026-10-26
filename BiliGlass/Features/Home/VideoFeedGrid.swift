import SwiftUI

/// 通用视频网格页。
///
/// 首页四流、历史、收藏夹内容都复用这一个视图：
/// 数据加载/翻页/刷新交给 VideoFeedStore，这里只负责四种状态（未登录/空/错误/列表）的呈现。
/// 点击卡片统一进视频详情页。
struct VideoFeedGrid: View {
    let store: VideoFeedStore
    /// 空列表中额外显示的说明文案
    var emptyHint: String = "这里还没有内容"
    /// 底部额外留白，避免被悬浮 TabBar 遮挡
    var bottomInset: CGFloat = 110
    /// 纵向滚动偏移回调，供首页顶部搜索栏做收起动画。
    /// 只有首页会传，历史/收藏等复用方不需要关心。
    var onScroll: ((CGFloat) -> Void)? = nil

    @State private var showLogin = false
    @State private var didAutoScroll = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.top, 8)
                    .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            // 用 onScrollGeometryChange 而不是 GeometryReader + PreferenceKey：
            // 后者每帧都要重排一次，长列表上代价明显。
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                onScroll?(offset)
            }
            .refreshable {
                await store.refresh()
            }
            .task {
                await store.loadIfNeeded()
                await autoScrollIfNeeded(proxy)
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .onChange(of: showLogin) { _, presented in
                // 登录成功后回到列表，需要重新拉一次（此前请求过被 -101 拒绝）
                guard !presented else { return }
                Task {
                    await AuthService.shared.refreshProfile()
                    await store.refresh()
                }
            }
        }
    }

    /// 调试用：`-debugScroll YES` 时首屏直接滚到第 9 张卡。
    ///
    /// 模拟器和真机都没法脚本化手势，只有这样才能稳定复现「列表滚动之后」
    /// 的底部状态（比如悬浮底栏下面漏出的那条底边）。
    private func autoScrollIfNeeded(_ proxy: ScrollViewProxy) async {
        guard DebugEntry.scroll, !didAutoScroll, store.items.count > 8 else { return }
        didAutoScroll = true
        // LazyVGrid 的行是滚动过程中才建出来的，立刻 scrollTo 会因为
        // 目标行还没渲染而被静默忽略，稍等一拍再滚
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.easeOut(duration: 0.4)) {
            proxy.scrollTo(store.items[8].id, anchor: .top)
        }
    }

    // MARK: - 状态分发

    @ViewBuilder
    private var content: some View {
        if store.needsLogin {
            loginGate
        } else if store.items.isEmpty {
            if store.isLoading {
                loadingState
            } else if let error = store.errorMessage {
                errorState(error)
            } else {
                emptyState
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.items) { model in
                    NavigationLink {
                        VideoDetailView(
                            bvid: model.id,
                            fallbackTitle: model.title,
                            resumeAt: model.progress
                        )
                    } label: {
                        VideoGridCard(model: model)
                    }
                    .buttonStyle(.plain)
                    .task {
                        await store.loadMoreIfNeeded(current: model)
                    }
                }
            }

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if store.isLoading {
            ProgressView()
                .tint(Theme.pink)
                .padding(.top, 16)
        } else if !store.hasMore, store.items.count > 6 {
            Text("没有更多了")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 16)
        }
    }

    // MARK: - 各状态

    private var loginGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.pink.opacity(0.85))
            Text("该内容需要登录后查看")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkDim)
            Button {
                showLogin = true
            } label: {
                Label("扫码登录", systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.pink)
            Text("正在加载…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 110)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.inkDim)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await store.refresh() }
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(Theme.inkFaint)
            Text(emptyHint)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 110)
    }
}
