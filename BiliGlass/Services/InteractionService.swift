import Foundation

/// 视频互动状态（点赞 / 投币 / 收藏）。
///
/// 三条接口都需要登录 + csrf，未登录时全部静默失败。
/// 交互上采用「乐观更新」：先改本地状态给用户即时反馈，请求失败再回滚，
/// 避免每次点击都要等一个网络往返。
@MainActor
@Observable
final class InteractionService {
    /// 单个视频最多 2 枚币
    static let maxCoin = 2

    var liked = false
    var coinCount = 0
    var favoured = false

    /// 任一请求进行中，避免连点把状态打乱
    var busy = false
    /// 顶部的短提示（"已点赞" / "投币成功" / "请先登录"）
    var toast: String?

    private var aid: Int?
    private var loaded = false

    var canInteract: Bool { CookieJar.shared.isLoggedIn }

    // MARK: - 读取初始状态

    func load(aid: Int) async {
        self.aid = aid
        guard !loaded else { return }
        await fetch(aid: aid)
    }

    private func fetch(aid: Int) async {
        guard CookieJar.shared.isLoggedIn else {
            liked = false
            coinCount = 0
            favoured = false
            loaded = true
            return
        }
        // 三个接口互相独立，并发取，任一失败保持默认值
        async let likeState = BiliAPI.shared.hasLike(aid: aid)
        async let coinState = BiliAPI.shared.hasCoin(aid: aid)
        async let favState = BiliAPI.shared.isFavoured(aid: aid)
        let (l, c, f) = await (likeState, coinState, favState)
        liked = l ?? false
        coinCount = c ?? 0
        favoured = f ?? false
        loaded = true
    }

    // MARK: - 操作

    func toggleLike(aid: Int) async {
        guard canInteract else { return show("请先登录后再点赞") }
        guard !busy else { return }
        let target = !liked
        busy = true
        liked = target
        do {
            try await BiliAPI.shared.setLike(aid: aid, liked: target)
            show(target ? "已点赞" : "已取消点赞")
        } catch {
            liked = !target
            show(error.localizedDescription)
        }
        busy = false
    }

    func addCoin(aid: Int) async {
        guard canInteract else { return show("请先登录后再投币") }
        guard !busy else { return }
        guard coinCount < Self.maxCoin else { return show("已经投过 2 枚币了") }
        busy = true
        let before = coinCount
        coinCount = min(Self.maxCoin, coinCount + 1)
        do {
            try await BiliAPI.shared.addCoin(aid: aid, count: 1)
            show("投币成功")
        } catch {
            coinCount = before
            show(error.localizedDescription)
        }
        busy = false
    }

    func toggleFavourite(aid: Int) async {
        guard canInteract else { return show("请先登录后再收藏") }
        guard !busy else { return }
        let target = !favoured
        busy = true
        favoured = target
        do {
            try await BiliAPI.shared.setFavourite(
                aid: aid,
                favourite: target,
                ownerMid: AuthService.shared.userID
            )
            show(target ? "已收藏" : "已取消收藏")
        } catch {
            favoured = !target
            show(error.localizedDescription)
        }
        busy = false
    }

    /// 用于从详情页展示数量增减，不做持久化
    func likeDelta() -> Int { liked ? 1 : 0 }

    // MARK: - 一键三连

    /// 三连本次实际做成了哪些动作，供 UI 决定要不要播动画和提示什么
    struct TripleOutcome {
        var liked = false
        var coins = 0
        var favoured = false

        var hasAction: Bool { liked || coins > 0 || favoured }
    }

    /// 一键三连：点赞 + 投满 2 枚币 + 收藏。
    ///
    /// 三项**并发**发出，任何一个失败都只回滚它自己，不牵连另外两项——
    /// B站这三条接口互相独立，串行等待只会让长按后转圈更久。
    /// `busy` 复用短按的锁，避免长按和短按同时改状态。
    func tripleAction(aid: Int) async -> TripleOutcome {
        guard canInteract else {
            show("请先登录后再三连")
            return TripleOutcome()
        }
        guard !busy else { return TripleOutcome() }

        let needLike = !liked
        let needCoins = Swift.max(0, Self.maxCoin - coinCount)
        let needFav = !favoured
        guard needLike || needCoins > 0 || needFav else {
            show("已经三连过啦")
            return TripleOutcome()
        }

        busy = true
        let beforeLike = liked
        let beforeCoin = coinCount
        let beforeFav = favoured

        // 先乐观更新，长按松手的瞬间按钮就该是「已三连」的样子
        liked = true
        coinCount = Swift.max(coinCount, Self.maxCoin)
        favoured = true

        let ownerMid = AuthService.shared.userID
        var failures: [String] = []

        await withTaskGroup(of: (String, Bool).self) { group in
            if needLike {
                group.addTask {
                    do {
                        try await BiliAPI.shared.setLike(aid: aid, liked: true)
                        return ("点赞", true)
                    } catch {
                        return ("点赞", false)
                    }
                }
            }
            if needCoins > 0 {
                let coins = needCoins
                group.addTask {
                    do {
                        try await BiliAPI.shared.addCoin(aid: aid, count: coins)
                        return ("投币", true)
                    } catch {
                        return ("投币", false)
                    }
                }
            }
            if needFav {
                group.addTask {
                    do {
                        try await BiliAPI.shared.setFavourite(
                            aid: aid, favourite: true, ownerMid: ownerMid
                        )
                        return ("收藏", true)
                    } catch {
                        return ("收藏", false)
                    }
                }
            }
            for await (name, ok) in group where !ok {
                failures.append(name)
            }
        }

        if failures.contains("点赞") { liked = beforeLike }
        if failures.contains("投币") { coinCount = beforeCoin }
        if failures.contains("收藏") { favoured = beforeFav }

        busy = false

        if failures.isEmpty {
            show("一键三连成功")
        } else if failures.count == 3 {
            show("三连失败，请稍后重试")
        } else {
            show("\(failures.joined(separator: "、"))失败，其余已生效")
        }

        return TripleOutcome(
            liked: needLike && !failures.contains("点赞"),
            coins: failures.contains("投币") ? 0 : needCoins,
            favoured: needFav && !failures.contains("收藏")
        )
    }

    // MARK: - 提示

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
