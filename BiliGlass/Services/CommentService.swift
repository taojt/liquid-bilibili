import Foundation

/// 评论区数据源。
///
/// 三块状态各自独立：
/// - 一级评论：`threads`（分页追加）+ `page` / `total`
/// - 楼中楼：每个 `Thread` 自己持有 `replies` 与展开状态，按需懒加载
/// - 点赞：`likes` 里存覆盖值，UI 优先读它，缺省才读接口返回的 `action` / `like`
///
/// 点赞单独用字典覆盖，而不是把 `BiliComment` 改成 var：
/// 接口结构体全部是 let，改一处就要把整棵树改成可变，反而容易在分页追加时丢状态。
@MainActor
@Observable
final class CommentService {
    /// 一条一级评论 + 它的楼中楼状态
    struct Thread: Identifiable {
        var comment: BiliComment
        var replies: [BiliComment] = []
        var repliesLoaded = false
        var expanded = false
        var repliesPage = 1

        var id: Int { comment.rpid }

        /// 接口给的 `rcount` 是回复总数；已加载数不足就还有更多
        var hasMoreReplies: Bool {
            replies.count < comment.rcount
        }

        /// 尚未加载时先展示接口夹带的预览回复，避免「点开才看到内容」的空窗
        var visibleReplies: [BiliComment] {
            repliesLoaded ? replies : comment.previewReplies
        }
    }

    struct LikeState {
        var liked: Bool
        var count: Int
    }

    var threads: [Thread] = []
    var pinnedThreads: [Thread] = []
    var total = 0
    var sort: CommentSort = .hot

    var isLoading = false
    var isLoadingMore = false
    var error: String?
    /// 只在真正拿到数据后置位；被取消不算加载过（见 README「取消 ≠ 网络故障」）
    var hasLoadedOnce = false
    /// 已经翻到底。不能拿「本次返回 0 条」以外的东西判断：
    /// 未登录时服务端只回 3 条一级评论，但 `page.count` 仍是真实总数（几万），
    /// 若只按总数判断会一直往下翻，页页都是空。
    var didReachEnd = false

    /// rpid -> 覆盖后的点赞状态
    private(set) var likes: [Int: LikeState] = [:]

    /// 调试用：当前走的是哪条接口（正式 / 兜底）
    var sourceLabel: String { usingMain ? "wbi" : "legacy" }

    private var aid: Int?
    private var page = 1
    private let pageSize = 20
    /// 是否走在正式接口（wbi/main）。它用游标翻页，与老接口的页码是两套模型。
    private var usingMain = false
    private var nextOffset = ""
    /// 正在点赞的 rpid，避免连点
    private var likeBusy: Set<Int> = []

    // MARK: - 读取

    func load(aid: Int, sort: CommentSort? = nil) async {
        if let sort { self.sort = sort }
        if self.aid != aid {
            // 换了视频，全部重来
            self.aid = aid
            threads = []
            pinnedThreads = []
            likes = [:]
            page = 1
            total = 0
            didReachEnd = false
            usingMain = false
            nextOffset = ""
            hasLoadedOnce = false
            error = nil
        }
        guard !hasLoadedOnce else { return }
        await fetchFirstPage()
    }

    func reload() async {
        page = 1
        await fetchFirstPage()
    }

    func setSort(_ newSort: CommentSort) async {
        guard newSort != sort else { return }
        sort = newSort
        await reload()
    }

    private func fetchFirstPage() async {
        guard let aid else { return }
        isLoading = true
        error = nil
        page = 1
        nextOffset = ""
        usingMain = false

        // 首选老接口：免签、免登录，登录态下正常一页 20 条
        // （未登录时服务端只给 3 条，但 `page.count` 仍是真实总数）
        do {
            let data = try await BiliAPI.shared.replyList(
                aid: aid, page: 1, pageSize: pageSize, sort: sort.legacyValue
            )
            apply(
                replies: data.replies,
                pinned: data.top,
                totalOverride: data.page?.count,
                reachedEnd: data.replies.count < pageSize
            )
            hasLoadedOnce = true
            isLoading = false
            return
        } catch {
            if error.isCancellation {
                isLoading = false
                return
            }
            // 老接口整体不可用时才退回网页端正式接口。
            // 它需要登录（未登录 -403）且翻页是游标模型，所以放在第二顺位。
            if let data = try? await BiliAPI.shared.replyMain(
                aid: aid, mode: sort.mainMode, offset: ""
            ) {
                usingMain = true
                nextOffset = data.cursor?.nextOffset ?? ""
                apply(
                    replies: data.replies,
                    pinned: data.topReplies,
                    totalOverride: data.cursor?.allCount,
                    reachedEnd: (data.cursor?.isEnd ?? true) || nextOffset.isEmpty
                )
                hasLoadedOnce = true
            } else {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// 落地首页结果：置顶与正常列表去重、算总数、判定是否到底
    private func apply(
        replies: [BiliComment],
        pinned: [BiliComment],
        totalOverride: Int?,
        reachedEnd: Bool
    ) {
        pinnedThreads = pinned
            .filter { !$0.message.isEmpty }
            .map { Thread(comment: $0) }
        threads = replies
            .filter { !$0.message.isEmpty }
            .map { Thread(comment: $0) }
        // 置顶有时会同时出现在正常列表里，去重避免展示两份
        let pinnedIDs = Set(pinnedThreads.map(\.id))
        if !pinnedIDs.isEmpty {
            threads.removeAll { pinnedIDs.contains($0.id) }
        }
        total = totalOverride ?? (threads.count + pinnedThreads.count)
        didReachEnd = reachedEnd
    }

    func loadMore() async {
        guard let aid, !isLoadingMore, !isLoading, !didReachEnd else { return }
        guard threads.count + pinnedThreads.count < total else { return }
        isLoadingMore = true

        if usingMain {
            guard !nextOffset.isEmpty else {
                didReachEnd = true
                isLoadingMore = false
                return
            }
            if let data = try? await BiliAPI.shared.replyMain(
                aid: aid, mode: sort.mainMode, offset: nextOffset
            ) {
                let existing = Set(threads.map(\.id))
                let fresh = data.replies
                    .filter { !$0.message.isEmpty && !existing.contains($0.rpid) }
                    .map { Thread(comment: $0) }
                threads.append(contentsOf: fresh)
                nextOffset = data.cursor?.nextOffset ?? ""
                if data.cursor?.isEnd == true || nextOffset.isEmpty || fresh.isEmpty {
                    didReachEnd = true
                }
            } else {
                didReachEnd = true
            }
            isLoadingMore = false
            return
        }

        let next = page + 1
        do {
            let data = try await BiliAPI.shared.replyList(
                aid: aid, page: next, pageSize: pageSize, sort: sort.legacyValue
            )
            let existing = Set(threads.map(\.id))
            let fresh = data.replies
                .filter { !$0.message.isEmpty && !existing.contains($0.rpid) }
                .map { Thread(comment: $0) }
            threads.append(contentsOf: fresh)
            page = next
            // 空页或不满一页都是到底。**不要**动 `total`：
            // 它来自服务端的总数，改小会让「评论 N」跟着错。
            if fresh.isEmpty || data.replies.count < pageSize {
                didReachEnd = true
            }
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
        isLoadingMore = false
    }

    // MARK: - 楼中楼

    /// 展开/收起。展开时若还没加载过就先拉第一页。
    func toggleReplies(threadID: Int) async {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        if threads[index].expanded {
            threads[index].expanded = false
            return
        }
        threads[index].expanded = true
        if !threads[index].repliesLoaded {
            await fetchReplies(at: index, page: 1)
        }
    }

    func loadMoreReplies(threadID: Int) async {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        guard threads[index].repliesLoaded else { return }
        guard threads[index].hasMoreReplies else { return }
        await fetchReplies(at: index, page: threads[index].repliesPage + 1)
    }

    private func fetchReplies(at index: Int, page: Int) async {
        guard let aid else { return }
        let root = threads[index].comment.rpid
        do {
            let data = try await BiliAPI.shared.replyReplies(
                aid: aid, root: root, page: page, pageSize: 10
            )
            guard threads.indices.contains(index), threads[index].id == root else { return }
            if page == 1 {
                threads[index].replies = data.replies
            } else {
                let existing = Set(threads[index].replies.map(\.id))
                threads[index].replies.append(
                    contentsOf: data.replies.filter { !existing.contains($0.rpid) }
                )
            }
            threads[index].repliesPage = page
            threads[index].repliesLoaded = true
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - 点赞

    func likeState(for comment: BiliComment) -> LikeState {
        likes[comment.rpid] ?? LikeState(liked: comment.liked, count: comment.like)
    }

    /// 一级评论与楼中楼共用：rpid 全局唯一，不必区分层级
    func toggleLike(comment: BiliComment) async {
        guard CookieJar.shared.isLoggedIn else {
            show("请先登录后再点赞")
            return
        }
        guard !likeBusy.contains(comment.rpid) else { return }
        likeBusy.insert(comment.rpid)

        let before = likeState(for: comment)
        let target = !before.liked
        // 乐观更新
        likes[comment.rpid] = LikeState(
            liked: target,
            count: Swift.max(0, before.count + (target ? 1 : -1))
        )

        if let aid {
            do {
                try await BiliAPI.shared.likeReply(aid: aid, rpid: comment.rpid, liked: target)
            } catch {
                likes[comment.rpid] = before
                show(error.localizedDescription)
            }
        }
        likeBusy.remove(comment.rpid)
    }

    // MARK: - 发表

    /// 发表评论或回复。成功返回 true，调用方据此关闭输入框。
    ///
    /// 成功后整页重拉第一页：新评论会因排序规则落到不同位置（按热度可能根本不在第一页），
    /// 本地插入很难和真实顺序一致，重拉最省事也最不容易出错。
    func post(message: String, root: Int = 0, parent: Int = 0) async -> Bool {
        guard let aid else { return false }
        guard CookieJar.shared.isLoggedIn else {
            show("请先登录后再评论")
            return false
        }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            show("评论内容不能为空")
            return false
        }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await BiliAPI.shared.addReply(
                aid: aid, message: text, root: root, parent: parent
            )
            show(root == 0 ? "评论已发布" : "回复已发布")
            await reload()
            // 楼中楼回复后把所在楼层展开，用户能立刻看到自己的回复
            if root != 0, let index = threads.firstIndex(where: { $0.id == root }) {
                threads[index].expanded = true
                await fetchReplies(at: index, page: 1)
            }
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    var isSending = false

    /// 一次性提示，与详情页其它 toast 复用同一位置。
    /// 用显式 `show(_:)` 而不是 `didSet`：`@Observable` 的属性观察器
    /// 会被宏转换干扰，写方法最稳。
    var toast: String?

    private var toastTask: Task<Void, Never>?

    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
