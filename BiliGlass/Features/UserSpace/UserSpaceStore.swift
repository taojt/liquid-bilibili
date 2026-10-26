import Foundation

/// UP 主投稿列表的数据源（分页）。
@MainActor
@Observable
final class UserSpaceStore {
    let mid: Int

    /// 投稿接口本身不带 UP 信息，卡片底部要靠外部补
    var upName: String?
    var upFace: String?

    var items: [VideoCellModel] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true

    private var page = 1
    private var hasLoadedOnce = false

    init(mid: Int, upName: String? = nil, upFace: String? = nil) {
        self.mid = mid
        self.upName = upName
        self.upFace = upFace
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await refresh()
    }

    /// 资料卡晚于投稿列表返回时，把名字/头像补进已渲染的卡片
    func applyUpInfo(name: String?, face: String?) {
        guard let name, !name.isEmpty else { return }
        upName = name
        if let face, !face.isEmpty { upFace = face }
        guard !items.isEmpty else { return }
        items = items.map { $0.withUp(name: upName, face: upFace) }
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
        isLoading = true
        errorMessage = nil
        do {
            let data = try await BiliAPI.shared.userArchives(mid: mid, page: page)
            let models = data.items.map { $0.cellModel(upName: upName, upFace: upFace) }
            if page == 1 {
                items = models
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: models.filter { !existing.contains($0.id) })
            }
            hasMore = data.hasMore
            page += 1
            hasLoadedOnce = true
        } catch {
            if error.isCancellation { isLoading = false; return }
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }
}
