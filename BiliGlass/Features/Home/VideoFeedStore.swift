import Foundation

/// 各类视频列表的统一数据源。
///
/// 首页四个分类、历史、收藏都复用同一套分页与状态机，
/// 只有 fetch 部分按数据源分支，避免每个页面写一遍加载/翻页/错误处理。
@MainActor
@Observable
final class VideoFeedStore {
    enum Source: Hashable {
        case recommend
        case following
        case popular
        case history
        case favorites(mediaID: Int)
    }

    let source: Source

    var items: [VideoCellModel] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true
    /// 该数据源需要登录但当前未登录
    var needsLogin = false

    private var page = 1
    private var historyMax = 0
    private var historyViewAt = 0
    private var dynamicOffset = ""
    private var hasLoadedOnce = false

    init(source: Source) {
        self.source = source
    }

    var requiresLogin: Bool {
        switch source {
        case .recommend, .popular: return false
        case .following, .history, .favorites: return true
        }
    }

    // MARK: - 对外

    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        page = 1
        historyMax = 0
        historyViewAt = 0
        dynamicOffset = ""
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

    // MARK: - 加载

    private func load() async {
        guard !isLoading else { return }

        if requiresLogin, !CookieJar.shared.isLoggedIn {
            needsLogin = true
            return
        }
        needsLogin = false

        isLoading = true
        errorMessage = nil
        do {
            let (fresh, more) = try await fetch()
            if page == 1 {
                items = fresh
            } else {
                // 去重，避免翻页时接口返回重复内容
                let existing = Set(items.map(\.id))
                items.append(contentsOf: fresh.filter { !existing.contains($0.id) })
            }
            hasMore = more
            page += 1
            hasLoadedOnce = true
        } catch {
            // 视图消失/切换 Tab 会让 SwiftUI 取消 .task，URLSession 随之抛 cancelled。
            // 这不是网络故障，既不该弹错误，也不能把 hasLoadedOnce 锁死导致再也无法重试。
            if error.isCancellation {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }

    private func fetch() async throws -> ([VideoCellModel], Bool) {
        switch source {
        case .recommend:
            let data = try await BiliAPI.shared.recommend(page: page)
            let models = (data.item ?? [])
                .filter { !$0.bvid.isEmpty }
                .map { VideoCellModel(video: $0) }
            return (models, !models.isEmpty)

        case .popular:
            let data = try await BiliAPI.shared.popular(page: page)
            let models = data.list.map { VideoCellModel(video: $0) }
            return (models, !(data.noMore ?? false))

        case .following:
            // 关注流走动态时间线的「视频」分类，老的 feed/video 端点已被反爬拦成 HTML
            let data = try await BiliAPI.shared.dynamicFeed(offset: dynamicOffset, type: "video")
            dynamicOffset = data.offset ?? ""
            var models: [VideoCellModel] = []
            for item in data.items ?? [] {
                guard let archive = item.modules?.dynamic?.major?.archive,
                      let bvid = archive.bvid, !bvid.isEmpty
                else { continue }
                let author = item.modules?.author
                models.append(
                    VideoCellModel(
                        id: bvid,
                        title: archive.title ?? "",
                        cover: archive.cover ?? "",
                        duration: archive.durationSeconds,
                        upName: author?.name,
                        upFace: author?.face,
                        publishedAt: author?.pubTs
                    )
                )
            }
            return (models, (data.hasMore ?? false) && !dynamicOffset.isEmpty)

        case .history:
            let data = try await BiliAPI.shared.history(max: historyMax, viewAt: historyViewAt)
            let cursor = data.cursor
            historyMax = cursor?.max ?? 0
            historyViewAt = cursor?.viewAt ?? 0

            var models: [VideoCellModel] = []
            for item in data.list ?? [] {
                // 只保留普通投稿，直播/专栏等暂不支持
                guard let ref = item.history,
                      let bvid = ref.bvid, !bvid.isEmpty,
                      (item.business ?? ref.business ?? "archive") == "archive"
                else { continue }
                models.append(
                    VideoCellModel(
                        id: bvid,
                        title: item.title ?? "",
                        cover: item.cover ?? "",
                        duration: item.duration ?? 0,
                        upName: item.authorName,
                        upFace: item.authorFace,
                        publishedAt: item.viewAt,
                        progress: item.progress
                    )
                )
            }
            let more = !models.isEmpty && historyMax > 0
            return (models, more)

        case .favorites(let mediaID):
            let data = try await BiliAPI.shared.favResources(mediaID: mediaID, page: page)
            var models: [VideoCellModel] = []
            for media in data.medias ?? [] {
                // 收藏夹里可能有已失效内容，标题为「已失效视频」
                guard let bvid = media.bvid, !bvid.isEmpty else { continue }
                models.append(
                    VideoCellModel(
                        id: bvid,
                        title: media.title ?? "",
                        cover: media.cover ?? "",
                        duration: media.duration ?? 0,
                        upName: media.upper?.name,
                        upFace: media.upper?.face,
                        viewCount: media.cntInfo?.play,
                        danmakuCount: media.cntInfo?.danmaku
                    )
                )
            }
            return (models, !(data.hasMore == false))
        }
    }
}
