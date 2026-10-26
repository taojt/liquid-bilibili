import Foundation

/// 关注动态时间线的数据源。
///
/// 和 `VideoFeedStore` 一样是「一次装载 + 下拉刷新 + 触底翻页」的状态机，
/// 区别在于条目不是纯视频，而是 UP 主动态（可能只有正文、可能是投稿卡片），
/// 因此单独一套模型和去重逻辑。
@MainActor
@Observable
final class DynamicStore {
    var items: [DynamicCell] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true
    var needsLogin = false

    private var offset = ""
    private var hasLoadedOnce = false

    // MARK: - 对外

    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        offset = ""
        hasMore = true
        items = []
        errorMessage = nil
        await load()
    }

    func loadMoreIfNeeded(current item: DynamicCell) async {
        guard hasMore, !isLoading else { return }
        guard let index = items.firstIndex(of: item), index >= items.count - 3 else { return }
        await load()
    }

    // MARK: - 加载

    private func load() async {
        guard !isLoading else { return }

        guard CookieJar.shared.isLoggedIn else {
            needsLogin = true
            return
        }
        needsLogin = false

        isLoading = true
        errorMessage = nil
        do {
            let data = try await BiliAPI.shared.dynamicFeed(offset: offset)
            offset = data.offset ?? ""
            let cells = (data.items ?? []).compactMap { DynamicCell(item: $0) }

            if items.isEmpty {
                items = cells
            } else {
                // 翻页时接口会重复返回边界条目，按动态 id 去重
                let existing = Set(items.map(\.id))
                items.append(contentsOf: cells.filter { !existing.contains($0.id) })
            }
            hasMore = (data.hasMore ?? false) && !offset.isEmpty
            hasLoadedOnce = true
        } catch {
            // 页面切换/视图重建导致的取消不是真错误，保持可重试
            if error.isCancellation { isLoading = false; return }
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }
}
