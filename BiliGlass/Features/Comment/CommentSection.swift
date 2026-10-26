import SwiftUI

/// 详情页的评论区区块。
///
/// 刻意不自己开 ScrollView：它挂在详情页原本的滚动视图里，
/// 嵌套滚动会让手势互相抢。列表用 `LazyVStack`，长列表只渲染可视范围。
struct CommentSection: View {
    let service: CommentService
    let aid: Int
    let upMid: Int

    @State private var activeSheet: ActiveSheet?
    /// 上一次自动续拉的时间，用于节流。
    /// 列表以动画方式被整体滚过时，`LazyVStack` 会连续创建多行、
    /// 每行都可能命中「最后一行」判断，没有节流会一口气拉好几页。
    @State private var lastAutoLoadAt = Date.distantPast

    /// 一次输入要发的目标：一级评论 root/parent 都是 0
    private struct ComposerTarget: Identifiable {
        let id = UUID()
        var root: Int = 0
        var parent: Int = 0
        var title: String = "发表评论"
        var placeholder: String = "发一条友善的评论"
    }

    /// 登录引导与输入框共用一个 sheet 状态。
    /// 同一个视图挂两个 `.sheet` 在部分系统版本上只有最后一个生效，
    /// 合并成一个枚举最稳，也天然保证同一时刻只有一个弹层。
    private enum ActiveSheet: Identifiable {
        case login
        case composer(ComposerTarget)

        var id: String {
            switch self {
            case .login: return "login"
            case .composer(let target): return target.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            writeEntry
            content
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .login:
                LoginView()
            case .composer(let target):
                CommentComposer(
                    title: target.title,
                    placeholder: target.placeholder
                ) { text in
                    await service.post(message: text, root: target.root, parent: target.parent)
                }
            }
        }
        .task {
            // 调试用：直接弹出输入框，便于截图检查布局（未登录也弹）
            guard DebugEntry.commentComposer else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            activeSheet = .composer(
                ComposerTarget(title: "回复 @平常人的一生", placeholder: "回复 @平常人的一生")
            )
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Theme.pink)
                .frame(width: 3, height: 13)
                .clipShape(.capsule)
            Text("评论")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if service.total > 0 {
                Text(service.total.biliCount)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
            if DebugEntry.comment {
                // 调试标记：确认走的是正式接口还是兜底接口
                Text("· \(service.sourceLabel) \(service.threads.count)条")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.pink)
            }

            Spacer(minLength: 0)

            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CommentSort.allCases) { option in
                Button {
                    Task { await service.setSort(option) }
                } label: {
                    if option == service.sort {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(service.sort.title)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.inkDim)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: - 写评论入口

    private var writeEntry: some View {
        Button {
            guard CookieJar.shared.isLoggedIn else {
                activeSheet = .login
                return
            }
            activeSheet = .composer(ComposerTarget())
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                Text("发一条友善的评论")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background {
                Capsule(style: .continuous)
                    .fill(Theme.ink.opacity(0.05))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.07), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表状态

    @ViewBuilder
    private var content: some View {
        if service.isLoading && !service.hasLoadedOnce {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在加载评论…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else if let error = service.error, service.threads.isEmpty, service.pinnedThreads.isEmpty {
            VStack(spacing: 8) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("重试") {
                    Task { await service.reload() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else if service.threads.isEmpty && service.pinnedThreads.isEmpty {
            Text("还没有评论，来抢个沙发")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            list
        }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(service.pinnedThreads) { thread in
                row(thread, pinned: true)
                divider
            }
            ForEach(service.threads) { thread in
                row(thread, pinned: false)
                    .onAppear {
                        // 滚到最后一条时自动续拉下一页，省去额外一次点击。
                        // 必须节流，否则动画滚动穿过列表会连拉数页。
                        guard thread.id == service.threads.last?.id else { return }
                        guard Date().timeIntervalSince(lastAutoLoadAt) > 2.0 else { return }
                        lastAutoLoadAt = Date()
                        Task { await service.loadMore() }
                    }
                divider
            }
            if service.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if !service.didReachEnd,
                      service.threads.count + service.pinnedThreads.count < service.total {
                Button {
                    Task { await service.loadMore() }
                } label: {
                    Text("查看更多评论")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.06))
            .frame(height: 0.5)
    }

    private func row(_ thread: CommentService.Thread, pinned: Bool) -> some View {
        CommentRowView(
            comment: thread.comment,
            thread: thread,
            service: service,
            upMid: upMid,
            pinned: pinned,
            onReply: { target in
                guard CookieJar.shared.isLoggedIn else {
                    activeSheet = .login
                    return
                }
                activeSheet = .composer(replyTarget(for: target))
            }
        )
    }

    /// 回复一级评论时 root = parent = 该评论；回复楼中楼时 root 取楼主的 rpid
    private func replyTarget(for comment: BiliComment) -> ComposerTarget {
        let root = comment.isRoot ? comment.rpid : comment.root
        return ComposerTarget(
            root: root,
            parent: comment.rpid,
            title: "回复 @\(comment.member.name)",
            placeholder: "回复 @\(comment.member.name)"
        )
    }
}
