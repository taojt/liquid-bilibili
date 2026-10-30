import SwiftUI

/// UP 主个人主页：资料头 + 投稿网格。
///
/// 资料来自 `x/web-interface/card`（免签可用），投稿来自 `series/recArchivesByKeywords`，
/// 两个接口都能在未登录状态下工作，因此这里不设登录门禁。
struct UserSpaceView: View {
    let mid: Int
    var fallbackName: String = ""
    var fallbackFace: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var card: UserCardData?
    @State private var cardError: String?
    @State private var store: UserSpaceStore
    @State private var isFollowing: Bool?
    @State private var followBusy = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(mid: Int, fallbackName: String = "", fallbackFace: String? = nil) {
        self.mid = mid
        self.fallbackName = fallbackName
        self.fallbackFace = fallbackFace
        _store = State(
            initialValue: UserSpaceStore(
                mid: mid,
                upName: fallbackName.isEmpty ? nil : fallbackName,
                upFace: fallbackFace
            )
        )
    }

    var body: some View {
        ZStack {
            CanvasBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    profileHeader
                    archiveSection
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 6)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await loadCard()
                await store.refresh()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .hidesFloatingTabBar()
        .task {
            await loadCard()
            await store.loadIfNeeded()
        }
    }

    // MARK: - 资料头

    private var profileHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                backButton

                Spacer(minLength: 0)

                if isFollowing != nil {
                    followButton
                }
            }

            VStack(spacing: 10) {
                avatar
                    .overlay(alignment: .bottomTrailing) { levelBadge }

                Text(card?.card?.name ?? fallbackName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                if let sign = card?.card?.sign, !sign.isEmpty {
                    Text(sign)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("UID \(mid)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }

                statLine
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var backButton: some View {
        GlassIconButton(systemName: "chevron.left", size: 32) { dismiss() }
            .accessibilityIdentifier("userSpaceBack")
    }

    private var avatar: some View {
        AsyncImage(url: (card?.card?.face ?? fallbackFace ?? "").biliImageURL) { phase in
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
        Text("LV\(card?.card?.level ?? 0)")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.pink, in: .capsule)
            .offset(x: 4, y: 2)
    }

    private var statLine: some View {
        HStack(spacing: 0) {
            statItem(card.map { $0.follower ?? 0 }, "粉丝")
            divider
            statItem(card.map { $0.archiveCount ?? 0 }, "投稿")
            divider
            statItem(card.map { $0.likeNum ?? 0 }, "获赞")
        }
        .padding(.top, 2)
    }

    private func statItem(_ value: Int?, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value == nil ? "—" : (value ?? 0).biliCount)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.1))
            .frame(width: 0.6, height: 22)
    }

    private var followButton: some View {
        Button {
            Task { await toggleFollow() }
        } label: {
            Text(isFollowing == true ? "已关注" : "关注")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFollowing == true ? Theme.inkDim : .white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassEffect(
                    isFollowing == true
                        ? .regular.interactive()
                        : .regular.tint(Theme.pink).interactive(),
                    in: .capsule
                )
        }
        .buttonStyle(.liquidPress)
        .disabled(followBusy)
    }

    // MARK: - 投稿

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.pink)
                    .frame(width: 3, height: 13)
                    .clipShape(.capsule)
                Text("TA 的投稿")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if store.isLoading, !store.items.isEmpty {
                    ProgressView().tint(Theme.pink).scaleEffect(0.7)
                }
            }

            if store.items.isEmpty {
                archivePlaceholder
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.items) { model in
                        NavigationLink {
                            VideoDetailView(bvid: model.id, fallbackTitle: model.title)
                        } label: {
                            VideoGridCard(model: model)
                        }
                        .buttonStyle(.cardPress)
                        .task { await store.loadMoreIfNeeded(current: model) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var archivePlaceholder: some View {
        if store.isLoading {
            ProgressView()
                .tint(Theme.pink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
        } else if let error = store.errorMessage {
            VStack(spacing: 10) {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            Text("TA 还没有投稿")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    // MARK: - 数据

    private func loadCard() async {
        if let fetched = try? await BiliAPI.shared.userCard(mid: mid) {
            card = fetched
            cardError = nil
            store.applyUpInfo(name: fetched.card?.name, face: fetched.card?.face)
        } else if card == nil {
            cardError = "无法获取 UP 主资料"
        }
        if isFollowing == nil {
            isFollowing = await BiliAPI.shared.isFollowing(mid: mid)
        }
    }

    private func toggleFollow() async {
        guard CookieJar.shared.isLoggedIn else {
            // 未登录不弹登录页，只提示——主页本身是可以匿名浏览的
            isFollowing = nil
            return
        }
        guard let current = isFollowing, !followBusy else { return }
        followBusy = true
        isFollowing = !current
        do {
            try await BiliAPI.shared.modifyRelation(mid: mid, follow: !current)
        } catch {
            isFollowing = current
        }
        followBusy = false
    }
}
