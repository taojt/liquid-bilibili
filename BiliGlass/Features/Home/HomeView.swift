import SwiftUI

/// 首页：顶部二级 Tab（推荐/关注/热门/直播）+ 分页容器 + 双列网格。
///
/// 二级 Tab 与分页器双向联动：
/// 点 Tab 会切页（带弹性动画），左右滑动翻页会反向更新 Tab 选中态。
///
/// 分页容器**不能**用 `TabView` 的 `.page` 样式：iOS 27 上它会像被隐藏的
/// 系统 TabBar 一样在屏幕底部留一条浅色背板（深色外观下就是一条白边），
/// 内容怎么铺都盖不住。换成原生横向 `ScrollView` + `.paging`，底色完全归自己管。
struct HomeView: View {
    @State private var selection = 0
    /// 分页器的滚动位置（id = 页码），与 selection 双向同步
    @State private var pageID: Int? = 0
    @State private var showLogin = false
    @State private var debugTarget: BVIDTarget?
    @State private var mySpaceTarget: MIDTarget?
    @State private var debugSearchPresented = false

    @State private var recommend = VideoFeedStore(source: .recommend)
    @State private var following = VideoFeedStore(source: .following)
    @State private var popular = VideoFeedStore(source: .popular)

    /// 顶栏是否处于收起态（搜索框缩成一个图标）。
    /// 收起阈值与展开阈值不同，形成回滞，避免在临界点反复抖动。
    @State private var collapsed = false
    private let collapseThreshold: CGFloat = 34
    private let expandThreshold: CGFloat = 12

    private let segments = ["推荐", "关注", "热门", "直播"]

    private var auth: AuthService { AuthService.shared }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    VideoFeedGrid(
                        store: recommend,
                        emptyHint: "推荐流暂时为空",
                        onScroll: handleScroll
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(0)
                    VideoFeedGrid(
                        store: following,
                        emptyHint: "还没有关注 UP 主的新投稿",
                        onScroll: handleScroll
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(1)
                    VideoFeedGrid(
                        store: popular,
                        emptyHint: "热门榜暂时为空",
                        onScroll: handleScroll
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(2)
                    LiveListView(onScroll: handleScroll)
                        .containerRelativeFrame(.horizontal)
                        .id(3)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageID)
            .scrollIndicators(.hidden)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: pageID) { _, new in
            // 手势翻页 → 反向更新 Tab 选中态
            guard let new, new != selection else { return }
            withAnimation(.snappy(duration: 0.26)) { selection = new }
        }
        .onChange(of: selection) { _, new in
            // 点 Tab → 滚到对应页（包一层动画才有平滑滚动；
            // SegmentTabs 的 withAnimation 传不到这里）
            if pageID != new {
                withAnimation(.snappy(duration: 0.26)) { pageID = new }
            }
            // 切段后新页面可能停在别的滚动位置，顶栏统一回到展开态
            withAnimation(.snappy(duration: 0.24)) { collapsed = false }
        }
        .navigationDestination(item: $debugTarget) { target in
            VideoDetailView(bvid: target.id, fallbackTitle: "调试播放")
        }
        .navigationDestination(item: $mySpaceTarget) { target in
            MySpaceView(mid: target.id)
        }
        .navigationDestination(isPresented: $debugSearchPresented) {
            SearchView()
        }
        .task {
            if DebugEntry.collapsed {
                collapsed = true
            }
            if let segment = DebugEntry.segment {
                selection = segment
            }
            if let bvid = DebugEntry.bvid {
                debugTarget = BVIDTarget(id: bvid)
            }
            if DebugEntry.search {
                debugSearchPresented = true
            }
            if let mid = DebugEntry.mySpaceMid {
                mySpaceTarget = MIDTarget(id: mid)
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
    }

    // MARK: - 顶栏

    /// 两行结构：上行是完整搜索框 + 头像，下行是二级 Tab。
    /// 上滑后上行整体收起，搜索入口缩成一枚小圆图标，挪到二级 Tab 右侧，
    /// 头像也跟着过去，避免「我的」入口丢失。
    private var header: some View {
        VStack(spacing: 8) {
            if !collapsed {
                HStack(spacing: 10) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.pink)

                    NavigationLink {
                        SearchView()
                    } label: {
                        searchEntry
                    }
                    .buttonStyle(.plain)

                    avatarButton
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 2)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing))
                    )
                )
            }

            HStack(spacing: 8) {
                SegmentTabs(titles: segments, selection: $selection)
                    .padding(.leading, Theme.contentPadding - 4)

                if collapsed {
                    compactSearchButton
                    avatarButton
                        .padding(.trailing, Theme.contentPadding)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// 上滑收起后的小搜索图标，独立对齐在「直播」右侧
    private var compactSearchButton: some View {
        NavigationLink {
            SearchView()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    /// 4 个分页共用同一个滚动回调，按上下阈值做回滞判断
    private func handleScroll(_ offset: CGFloat) {
        let shouldCollapse: Bool
        if collapsed {
            shouldCollapse = offset > expandThreshold
        } else {
            shouldCollapse = offset > collapseThreshold
        }
        guard shouldCollapse != collapsed else { return }
        withAnimation(.snappy(duration: 0.26)) {
            collapsed = shouldCollapse
        }
    }

    private var searchEntry: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text("搜索视频、UP 主")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var avatarButton: some View {
        Group {
            if auth.isLoggedIn {
                NavigationLink {
                    MySpaceView()
                } label: {
                    avatarCircle
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showLogin = true
                } label: {
                    avatarCircle
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avatarCircle: some View {
        Group {
            if let face = auth.profile?.face, let url = face.biliImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 30, height: 30)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(Theme.ink.opacity(0.12), lineWidth: 0.6)
                }
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 30, height: 30)
            .glassEffect(.regular.tint(Theme.pink).interactive(), in: .circle)
    }
}
