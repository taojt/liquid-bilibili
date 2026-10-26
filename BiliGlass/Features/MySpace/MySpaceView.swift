import SwiftUI

/// 「我的主页」。
///
/// 与「我的」Tab 的分工：
/// - 我的 Tab = 设置/会话/外观这些**本地**的东西；
/// - 我的主页 = 账号**内容**（属性 + 历史 + 收藏 + 点赞），结构对齐 UP 主主页。
///
/// 首页右上角头像进这里，UP 主主页进 `UserSpaceView`，两者视觉语言一致。
struct MySpaceView: View {
    @Environment(\.dismiss) private var dismiss

    /// 指定 mid 时用它（调试直达 / 未来支持看别人的主页）；
    /// 不指定就是当前登录账号。
    private let overrideMid: Int?

    init(mid: Int? = nil) {
        self.overrideMid = mid
    }

    private var auth: AuthService { AuthService.shared }

    enum Section: String, CaseIterable, Identifiable {
        case history
        case favorites
        case likes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "历史"
            case .favorites: return "收藏"
            case .likes: return "点赞"
            }
        }

        var icon: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .favorites: return "star.fill"
            case .likes: return "hand.thumbsup.fill"
            }
        }
    }

    @State private var section: Section = .history

    @State private var card: UserCardData?
    @State private var info: MyInfoData?
    @State private var relation: RelationStatData?
    @State private var isLoadingMeta = true

    @State private var history = VideoFeedStore(source: .history)
    @State private var liked = LikedVideoStore()

    @State private var folders: [FavFolder] = []
    @State private var isLoadingFolders = false
    @State private var folderError: String?
    @State private var foldersLoaded = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var mid: Int {
        overrideMid ?? auth.userID ?? card?.card?.mid ?? 0
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    attributeCard
                    sectionBar
                    sectionContent
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await loadMeta(force: true)
                switch section {
                case .history: await history.refresh()
                case .likes: await liked.refresh()
                case .favorites:
                    foldersLoaded = false
                    await loadFolders()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .hidesFloatingTabBar()
        .task {
            if let tab = DebugEntry.mySpaceTab, let target = Section(rawValue: tab) {
                section = target
            }
            await loadMeta()
        }
        .task(id: section) { await loadSection() }
    }

    // MARK: - 资料头

    private var profileCard: some View {
        VStack(spacing: 12) {
            HStack {
                GlassIconButton(systemName: "chevron.left", size: 32) { dismiss() }
                Spacer(minLength: 0)
                NavigationLink {
                    FavoritesView()
                } label: {
                    Text("收藏夹管理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            avatar
                .overlay(alignment: .bottomTrailing) { levelBadge }

            Text(displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Text(signText)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 15)

            statLine
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var displayName: String {
        card?.card?.name ?? auth.profile?.uname ?? "未登录"
    }

    private var signText: String {
        if let sign = card?.card?.sign, !sign.isEmpty { return sign }
        return mid > 0 ? "UID \(mid)" : "登录后可查看个人主页"
    }

    private var avatar: some View {
        AsyncImage(url: (card?.card?.face ?? auth.profile?.face ?? "").biliImageURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 68, height: 68)
                    .glassEffect(.regular.tint(Theme.purple.opacity(0.8)), in: .circle)
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(.circle)
    }

    private var levelBadge: some View {
        let level = card?.card?.level ?? info?.level ?? 0
        return Text("LV\(level)")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.pink, in: .capsule)
            .offset(x: 4, y: 2)
    }

    private var statLine: some View {
        HStack(spacing: 0) {
            statItem(relation?.following, "关注")
            verticalDivider
            statItem(relation?.follower ?? card?.follower, "粉丝")
            verticalDivider
            statItem(card?.likeNum, "获赞")
        }
        .padding(.top, 2)
    }

    private func statItem(_ value: Int?, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map(\.biliCount) ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.1))
            .frame(width: 0.6, height: 22)
    }

    // MARK: - 属性信息

    /// 账号属性。这些字段只有登录态才有（`space/myinfo`），
    /// 缺失的项直接不渲染，不占位成「—」，避免整块看起来很空。
    private var attributeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.pink)
                    .frame(width: 3, height: 12)
                    .clipShape(.capsule)
                Text("账号属性")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if isLoadingMeta {
                    ProgressView().tint(Theme.pink).scaleEffect(0.6)
                }
            }

            FlowRow(spacing: 8, lineSpacing: 8) {
                attributeChip("UID", value: mid > 0 ? "\(mid)" : "—", icon: "number")
                if let coins = info?.coins {
                    attributeChip("硬币", value: String(format: "%.1f", coins), icon: "circlebadge.2.fill")
                }
                if let level = info?.level ?? card?.card?.level {
                    attributeChip("等级", value: "LV\(level)", icon: "star.circle.fill")
                }
                if let sex = info?.sex {
                    attributeChip("性别", value: sex.isEmpty ? "保密" : sex, icon: "person.fill")
                }
                if let birthday = info?.birthday, birthday > 0 {
                    attributeChip("生日", value: birthday.birthdayText, icon: "gift.fill")
                }
                attributeChip("粉丝", value: (relation?.follower ?? card?.follower).map(\.biliCount) ?? "—", icon: "person.2.fill")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func attributeChip(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.pink.opacity(0.9))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.ink.opacity(0.06), in: .capsule)
    }

    // MARK: - 分段

    private var sectionBar: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases) { item in
                let active = section == item
                Button {
                    withAnimation(.snappy(duration: 0.24)) { section = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? .white : Theme.inkDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if active {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.pink, Theme.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        } else {
                            Capsule(style: .continuous)
                                .fill(Theme.ink.opacity(0.06))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 分段内容

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .history:
            videoGrid(
                items: history.items,
                isLoading: history.isLoading,
                errorMessage: history.errorMessage,
                needsLogin: history.needsLogin,
                emptyHint: "还没有观看记录",
                retry: { Task { await history.refresh() } },
                loadMore: { model in Task { await history.loadMoreIfNeeded(current: model) } }
            )
        case .likes:
            videoGrid(
                items: liked.items,
                isLoading: liked.isLoading,
                errorMessage: liked.errorMessage,
                needsLogin: liked.needsLogin,
                emptyHint: "还没有点赞过视频",
                retry: { Task { await liked.refresh() } },
                loadMore: { model in Task { await liked.loadMoreIfNeeded(current: model) } }
            )
        case .favorites:
            folderList
        }
    }

    @ViewBuilder
    private func videoGrid(
        items: [VideoCellModel],
        isLoading: Bool,
        errorMessage: String?,
        needsLogin: Bool,
        emptyHint: String,
        retry: @escaping () -> Void,
        loadMore: @escaping (VideoCellModel) -> Void
    ) -> some View {
        if needsLogin {
            stateHint(
                icon: "lock.circle.fill",
                text: "登录后才能查看",
                actionTitle: nil,
                action: nil
            )
        } else if items.isEmpty {
            if isLoading {
                ProgressView().tint(Theme.pink).padding(.vertical, 60)
            } else if let errorMessage {
                stateHint(icon: "wifi.exclamationmark", text: errorMessage, actionTitle: "重试", action: retry)
            } else {
                stateHint(icon: "tray", text: emptyHint, actionTitle: nil, action: nil)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { model in
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
                    .task { loadMore(model) }
                }
            }
        }
    }

    private func stateHint(
        icon: String,
        text: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkFaint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - 收藏夹

    @ViewBuilder
    private var folderList: some View {
        if isLoadingFolders, folders.isEmpty {
            ProgressView().tint(Theme.pink).padding(.vertical, 60)
        } else if let folderError, folders.isEmpty {
            stateHint(
                icon: "wifi.exclamationmark",
                text: folderError,
                actionTitle: "重试",
                action: { Task { await loadFolders(force: true) } }
            )
        } else if folders.isEmpty {
            stateHint(icon: "star", text: "还没有收藏夹", actionTitle: nil, action: nil)
        } else {
            VStack(spacing: 10) {
                ForEach(folders) { folder in
                    NavigationLink {
                        FavFolderContentView(mediaID: folder.id, title: folder.title)
                    } label: {
                        folderRow(folder)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func folderRow(_ folder: FavFolder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.pink)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(Theme.pink.opacity(0.26)), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\((folder.mediaCount ?? 0).biliCount) 个内容")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - 数据

    private func loadMeta(force: Bool = false) async {
        guard mid > 0 else {
            isLoadingMeta = false
            return
        }
        if !force, card != nil { return }
        isLoadingMeta = true
        async let cardTask = BiliAPI.shared.userCard(mid: mid)
        async let relationTask = BiliAPI.shared.relationStat(mid: mid)
        // myinfo 需要登录态，失败不影响其它两块
        async let infoTask = try? BiliAPI.shared.myInfo()

        card = try? await cardTask
        relation = try? await relationTask
        info = await infoTask
        isLoadingMeta = false
    }

    private func loadSection() async {
        switch section {
        case .history:
            await history.loadIfNeeded()
        case .likes:
            await liked.loadIfNeeded()
        case .favorites:
            await loadFolders()
        }
    }

    private func loadFolders(force: Bool = false) async {
        guard mid > 0 else { return }
        if foldersLoaded, !force { return }
        isLoadingFolders = true
        folderError = nil
        do {
            let data = try await BiliAPI.shared.favFolders(mid: mid)
            folders = data.list ?? []
            foldersLoaded = true
        } catch {
            if !error.isCancellation {
                folderError = error.localizedDescription
            }
        }
        isLoadingFolders = false
    }
}

// MARK: - 简易流式布局

/// 属性 chip 用的自动换行容器。
/// 行数不定、每行宽度不定，用 HStack + 手算换行太脆，这里直接按可用宽度流式排。
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = Swift.max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = Swift.max(lineHeight, size.height)
        }
        widest = Swift.max(widest, x > 0 ? x - spacing : 0)
        return CGSize(width: Swift.min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = Swift.max(lineHeight, size.height)
        }
    }
}
