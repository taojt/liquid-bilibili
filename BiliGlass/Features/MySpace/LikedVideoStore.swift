import Foundation

/// 「我的主页 → 点赞」的数据源。
///
/// 接口是 `x/space/like/video?vmid=`，条目结构与投稿列表一致，
/// 因此复用 `SpaceArchive` 解码；区别只在于作者信息取的是视频自己的 owner，
/// 而不是页面归属人（点赞的视频当然不一定是自己投的）。
@MainActor
@Observable
final class LikedVideoStore {
    var items: [VideoCellModel] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true
    /// 未登录（拿不到 UID）时为 true，界面走登录引导
    var needsLogin = false

    private var page = 1
    private var hasLoadedOnce = false
    private var mid: Int { AuthService.shared.userID ?? 0 }

    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        page = 1
        hasMore = true
        items = []
        errorMessage = nil
        await load()
    }

    func loadMoreIfNeeded(current item: VideoCellModel) async {
        guard hasMore, !isLoading else { return }
        guard let index = items.firstIndex(of: item), index >= items.count - 4 else { return }
        await load()
    }

    private func load() async {
        guard !isLoading else { return }
        let mid = self.mid
        guard mid > 0 else {
            needsLogin = true
            hasMore = false
            return
        }
        needsLogin = false
        isLoading = true
        errorMessage = nil
        do {
            let data = try await BiliAPI.shared.likeVideos(mid: mid, page: page)
            let models = (data.list ?? []).filter { !$0.bvid.isEmpty }.map { $0.cellModel() }
            if page == 1 {
                items = models
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: models.filter { !existing.contains($0.id) })
            }
            // 接口不返总数时用「这一页有没有满」判断还有没有下一页
            hasMore = !models.isEmpty
            page += 1
            hasLoadedOnce = true
        } catch {
            if error.isCancellation {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }
}
