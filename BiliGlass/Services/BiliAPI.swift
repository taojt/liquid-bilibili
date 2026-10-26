import Foundation

/// B站接口门面。
///
/// 所有端点都是非公开接口，参数与返回结构可能随时变化。
/// 因此这一层刻意保持薄：只做参数拼装与签名，不做业务判断，
/// 未来某端点变更时替换单个方法即可。
actor BiliAPI {
    static let shared = BiliAPI()

    private let web = "https://api.bilibili.com"
    private let passport = "https://passport.bilibili.com"

    // WBI 密钥按天轮换，缓存 6 小时后强制刷新
    private var cachedMixinKey: String?
    private var mixinKeyFetchedAt: Date?
    private let mixinKeyTTL: TimeInterval = 6 * 3600

    // MARK: - 首页

    /// 热门视频列表（无需签名，最稳的一条流）
    func popular(page: Int = 1, pageSize: Int = 20) async throws -> PopularData {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/popular",
            query: ["ps": "\(pageSize)", "pn": "\(page)"],
            as: PopularData.self
        )
    }

    // MARK: - 视频详情

    func videoDetail(bvid: String) async throws -> VideoDetail {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/view",
            query: ["bvid": bvid],
            as: VideoDetail.self
        )
    }

    // MARK: - 播放地址

    /// 取 DASH 播放流。
    /// 注意：playurl 必须传 avid + cid，传 bvid 会失败；fnval=4048 才能拿全画质档位。
    func playURL(aid: Int, cid: Int, qn: Int = 80) async throws -> PlayURLData {
        var params: [String: String] = [
            "avid": "\(aid)",
            "cid": "\(cid)",
            "qn": "\(qn)",
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1"
        ]

        // 优先走带签名的端点
        if let key = try? await mixinKey() {
            let signed = WBISigner.sign(params: params, mixinKey: key)
            if let data = try? await HTTPClient.shared.get(
                "\(web)/x/player/wbi/playurl",
                query: signed,
                as: PlayURLData.self
            ) {
                return data
            }
        }

        // 签名不可用时退回普通端点。注意不要加 platform=html5，
        // 那个组合只返回单文件 mp4（durl），拿不到 DASH 分离流。
        return try await HTTPClient.shared.get(
            "\(web)/x/player/playurl",
            query: params,
            as: PlayURLData.self
        )
    }

    /// 取 durl 单文件 MP4 流。
    ///
    /// 相比 DASH，单文件 MP4 由 AVFoundation 原生支持，随机访问稳定，
    /// 不需要自己处理 fMP4 的索引段。画质由 qn 决定，需要登录态才有高清。
    func playURLMp4(aid: Int, cid: Int, qn: Int = 64) async throws -> PlayURLData {
        let params: [String: String] = [
            "avid": "\(aid)",
            "cid": "\(cid)",
            "qn": "\(qn)",
            "fnval": "1",
            "fnver": "0",
            "fourk": "1",
            "platform": "html5",
            "high_quality": "1"
        ]

        if let key = try? await mixinKey() {
            let signed = WBISigner.sign(params: params, mixinKey: key)
            if let data = try? await HTTPClient.shared.get(
                "\(web)/x/player/wbi/playurl",
                query: signed,
                as: PlayURLData.self
            ) {
                return data
            }
        }
        return try await HTTPClient.shared.get(
            "\(web)/x/player/playurl",
            query: params,
            as: PlayURLData.self
        )
    }

    // MARK: - 推荐流

    /// 首页推荐（需要 WBI 签名）。返回的是个性化推荐，未登录也能拿到一份通用流。
    func recommend(page: Int = 1, pageSize: Int = 20) async throws -> RecommendData {
        var params: [String: String] = [
            "ps": "\(pageSize)",
            "fresh_type": "3",
            "feed_version": "V8",
            "fresh_idx": "\(page)",
            "fresh_idx_1h": "\(page)",
            "brush": "0",
            "homepage_ver": "1",
            "web_location": "1430650"
        ]
        if let key = try? await mixinKey() {
            params = WBISigner.sign(params: params, mixinKey: key)
        }
        return try await HTTPClient.shared.get(
            "\(web)/x/web-interface/wbi/index/top/feed/rcmd",
            query: params,
            as: RecommendData.self
        )
    }

    // MARK: - 关注动态

    /// 关注 UP 主的动态时间线（视频、图文、转发混排）。
    ///
    /// 必须登录，未登录直接 -101。注意老的 `feed/video` 端点现在会被反爬拦成一段 HTML，
    /// 不能再当主路径，只在 `feed/all` 拿不到时兜底试一次。
    func dynamicFeed(offset: String = "", type: String = "all") async throws -> DynFeedData {
        var params: [String: String] = [
            "type": type,
            "page": "1",
            "offset": offset,
            "timezone_offset": "-480",
            "features": "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,"
                + "decorationCard,onlyfansAssetsV2,ugcDelete,onlyfansQaCard",
            "web_location": "333.999"
        ]
        if let key = try? await mixinKey() {
            params = WBISigner.sign(params: params, mixinKey: key)
        }
        return try await HTTPClient.shared.get(
            "\(web)/x/polymer/web-dynamic/v1/feed/all",
            query: params,
            as: DynFeedData.self
        )
    }

    // MARK: - 历史记录

    /// 观看历史。cursor 传上一页返回的 max / view_at 做翻页。
    func history(max: Int = 0, viewAt: Int = 0, pageSize: Int = 20) async throws -> HistoryData {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/history/cursor",
            query: [
                "max": "\(max)",
                "view_at": "\(viewAt)",
                "ps": "\(pageSize)",
                "type": "archive"
            ],
            as: HistoryData.self
        )
    }

    // MARK: - 收藏

    func favFolders(mid: Int) async throws -> FavFolderListData {
        try await HTTPClient.shared.get(
            "\(web)/x/v3/fav/folder/created/list-all",
            query: ["up_mid": "\(mid)", "web_location": "333.1387"],
            as: FavFolderListData.self
        )
    }

    func favResources(mediaID: Int, page: Int = 1, pageSize: Int = 20) async throws -> FavResourceData {
        try await HTTPClient.shared.get(
            "\(web)/x/v3/fav/resource/list",
            query: [
                "media_id": "\(mediaID)",
                "ps": "\(pageSize)",
                "pn": "\(page)",
                "platform": "web",
                "order": "mtime",
                "type": "0",
                "tid": "0"
            ],
            as: FavResourceData.self
        )
    }

    // MARK: - 相关推荐

    /// 播放页的相关推荐。注意这个接口的 data 直接是数组，不是对象。
    func relatedVideos(bvid: String) async throws -> [BiliVideo] {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/archive/related",
            query: ["bvid": bvid],
            as: [BiliVideo].self
        )
    }

    // MARK: - 直播

    /// 直播分区列表。
    ///
    /// 注意：新版 `xlive/web-interface/v1/second/getList` 现在需要额外风控参数，
    /// 直接请求会被判 -352。老接口 `room/v1/area/getRoomList` 仍然免签可用，
    /// 且 data 直接就是数组。
    func liveList(page: Int = 1, pageSize: Int = 20) async throws -> [LiveRoom] {
        try await HTTPClient.shared.get(
            "https://api.live.bilibili.com/room/v1/area/getRoomList",
            query: [
                "platform": "web",
                "parent_area_id": "0",
                "area_id": "0",
                "sort_type": "online",
                "page": "\(page)",
                "page_size": "\(pageSize)"
            ],
            as: [LiveRoom].self,
            referer: "https://live.bilibili.com/"
        )
    }

    /// 直播拉流地址。
    /// 老接口 room/v1/Room/playUrl 不需要 WBI 签名，返回 h5 平台的 m3u8，
    /// AVPlayer 原生可播，因此直播链路比点播短得多。
    func livePlayURL(roomID: Int) async throws -> LivePlayData {
        try await HTTPClient.shared.get(
            "https://api.live.bilibili.com/room/v1/Room/playUrl",
            query: ["cid": "\(roomID)", "platform": "h5", "quality": "4"],
            as: LivePlayData.self,
            referer: "https://live.bilibili.com/"
        )
    }

    /// 短号换成真实房间号。弹幕鉴权必须用真实 room_id，用短号会认证失败。
    func liveRoomInit(roomID: Int) async throws -> RoomInitData {
        try await HTTPClient.shared.get(
            "https://api.live.bilibili.com/room/v1/Room/room_init",
            query: ["id": "\(roomID)"],
            as: RoomInitData.self,
            referer: "https://live.bilibili.com/"
        )
    }

    /// 弹幕服务器地址 + 鉴权 token。
    /// 2024 年起这个接口也要 WBI 签名，未签名直接 -352。
    func liveDanmuInfo(roomID: Int) async throws -> DanmuInfoData {
        var params: [String: String] = ["id": "\(roomID)", "type": "0"]
        if let key = try? await mixinKey() {
            params = WBISigner.sign(params: params, mixinKey: key)
        }
        return try await HTTPClient.shared.get(
            "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo",
            query: params,
            as: DanmuInfoData.self,
            referer: "https://live.bilibili.com/"
        )
    }

    // MARK: - 搜索

    /// 综合搜索（只取视频）。
    /// 这个端点必须 WBI 签名，未签名会被反爬拦成一段 HTML 而不是 JSON。
    func searchVideos(keyword: String, page: Int = 1, pageSize: Int = 20) async throws -> SearchData {
        var params: [String: String] = [
            "search_type": "video",
            "keyword": keyword,
            "page": "\(page)",
            "page_size": "\(pageSize)",
            "platform": "pc",
            "web_location": "1430654"
        ]
        if let key = try? await mixinKey() {
            params = WBISigner.sign(params: params, mixinKey: key)
        }
        return try await HTTPClient.shared.get(
            "\(web)/x/web-interface/wbi/search/type",
            query: params,
            as: SearchData.self
        )
    }

    /// 热搜榜，免签
    func searchHotWords(limit: Int = 10) async throws -> SearchSquareData {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/search/square",
            query: ["limit": "\(limit)"],
            as: SearchSquareData.self
        )
    }

    // MARK: - 弹幕

    /// 弹幕 XML。
    /// 响应头带 `Content-Encoding: deflate`，URLSession 会自动解压，
    /// 所以这里拿到的是明文 XML。用 comment 域名而不是 dm/list.so，
    /// 后者有时间窗口限制，老视频会返回空列表。
    func danmakuXML(cid: Int) async throws -> Data {
        let (data, _) = try await HTTPClient.shared.getRaw(
            "https://comment.bilibili.com/\(cid).xml",
            referer: "https://www.bilibili.com"
        )
        return data
    }

    // MARK: - 设备指纹

    /// 获取 buvid3 / buvid4。很多接口（历史、动态、推荐）缺少设备指纹时会被风控降级，
    /// 因此启动时取一次并随 Cookie 一起持久化。
    func ensureFingerprint() async {
        let hasBuvid = await MainActor.run { CookieJar.shared.cookies["buvid3"] != nil }
        guard !hasBuvid else { return }
        do {
            let data = try await HTTPClient.shared.get(
                "\(web)/x/frontend/finger/spi",
                as: FingerprintData.self
            )
            await MainActor.run {
                if let b3 = data.b3, !b3.isEmpty { CookieJar.shared.set("buvid3", b3) }
                if let b4 = data.b4, !b4.isEmpty { CookieJar.shared.set("buvid4", b4) }
            }
        } catch {
            // 取不到不阻塞主流程，接口会退化处理
        }
    }

    // MARK: - 用户信息

    /// 登录态与 WBI 密钥来源。
    /// 注意：未登录时本接口 code 为 -101，但 data 中仍包含 wbi_img，
    /// 因此这里不看 code，只要 data 能解出来就返回。
    func nav() async -> NavData? {
        do {
            let (data, _) = try await HTTPClient.shared.getRaw("\(web)/x/web-interface/nav")
            let wrapper = try JSONDecoder().decode(BiliResponse<NavData>.self, from: data)
            return wrapper.data
        } catch {
            return nil
        }
    }

    // MARK: - UP 主主页

    /// UP 主资料卡。免签、未登录可用，是最稳的一条（`space/wbi/acc/info` 现在常被判 -352）。
    func userCard(mid: Int) async throws -> UserCardData {
        try await HTTPClient.shared.get(
            "\(web)/x/web-interface/card",
            query: ["mid": "\(mid)"],
            as: UserCardData.self
        )
    }

    // MARK: - 我的主页

    /// 自己的账号资料（硬币、生日、等级等属性）。仅登录态可用。
    /// 拿不到就当作没有——页面顶部还有 `card` 兜底，不能因为这一条失败就空白。
    func myInfo() async throws -> MyInfoData {
        try await HTTPClient.shared.get(
            "\(web)/x/space/myinfo",
            as: MyInfoData.self
        )
    }

    /// 关注 / 粉丝数。免签，未登录也能查。
    func relationStat(mid: Int) async throws -> RelationStatData {
        try await HTTPClient.shared.get(
            "\(web)/x/relation/stat",
            query: ["vmid": "\(mid)"],
            as: RelationStatData.self
        )
    }

    /// 某个用户点赞过的视频。条目结构与投稿列表一致，直接复用 `SpaceArchive`。
    func likeVideos(mid: Int, page: Int = 1, pageSize: Int = 20) async throws -> LikeVideoData {
        try await HTTPClient.shared.get(
            "\(web)/x/space/like/video",
            query: [
                "vmid": "\(mid)",
                "pn": "\(page)",
                "ps": "\(pageSize)"
            ],
            as: LikeVideoData.self
        )
    }

    /// UP 主投稿列表。
    ///
    /// 首选 `series/recArchivesByKeywords`：免签、分页清晰、字段够用。
    /// 兜底 `space/wbi/arc/search`：网页端正式接口，需要 WBI 签名 + 登录态，
    /// 并且少了 dm_* 这几个「雾霾参数」会被判 412 反爬。
    func userArchives(mid: Int, page: Int = 1, pageSize: Int = 20) async throws -> UserArchivePage {
        do {
            let data = try await HTTPClient.shared.get(
                "\(web)/x/series/recArchivesByKeywords",
                query: [
                    "mid": "\(mid)",
                    "keywords": "",
                    "ps": "\(pageSize)",
                    "pn": "\(page)",
                    "orderby": "pubdate"
                ],
                as: SpaceArchiveData.self
            )
            let items = (data.archives ?? []).filter { !$0.bvid.isEmpty }
            let total = data.page?.total ?? 0
            return UserArchivePage(
                items: items,
                hasMore: !items.isEmpty && page * pageSize < total
            )
        } catch {
            var params: [String: String] = [
                "mid": "\(mid)",
                "ps": "\(pageSize)",
                "pn": "\(page)",
                "order": "pubdate",
                "tid": "0",
                "keyword": "",
                "platform": "web",
                "web_location": "1550101",
                "order_avoided": "true",
                "dm_img_list": "[]",
                "dm_img_str": "V2ViR0wgMS4wIChPcGVuR0wgRVMgMi4wIENocm9taXVtKQ",
                "dm_cover_img_str": "QU5HTEUgKEFwcGxlLCBBcHBsZSBNMSwgT3BlbkdMIGVuZ2luZSA0LjEp",
                "dm_img_inter": "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}"
            ]
            if let key = try? await mixinKey() {
                params = WBISigner.sign(params: params, mixinKey: key)
            }
            let data = try await HTTPClient.shared.get(
                "\(web)/x/space/wbi/arc/search",
                query: params,
                as: SpaceArcSearchData.self
            )
            let items = (data.list?.vlist ?? [])
                .map { SpaceArchive(arcItem: $0) }
                .filter { !$0.bvid.isEmpty }
            let count = data.page?.count ?? 0
            return UserArchivePage(
                items: items,
                hasMore: !items.isEmpty && page * pageSize < count
            )
        }
    }

    // MARK: - 评论

    /// 网页端正式的评论列表（`wbi/main`）。
    ///
    /// 唯一能翻完整列表的入口，但**必须登录**：未登录直接 `-403 访问权限不足`。
    /// 翻页靠 `pagination_str` 里的游标，不是页码——`offset` 传上一页 `cursor` 给的
    /// `next_offset`，首页传空串。注意要把它作为**一段 JSON 字符串**编码进 query。
    func replyMain(aid: Int, mode: Int, offset: String) async throws -> CommentMainData {
        let pagination = "{\"offset\":\"\(offset)\"}"
        var params: [String: String] = [
            "oid": "\(aid)",
            "type": "1",
            "mode": "\(mode)",
            "pagination_str": pagination,
            "plat": "1",
            "web_location": "1315875"
        ]
        if let key = try? await mixinKey() {
            params = WBISigner.sign(params: params, mixinKey: key)
        }
        return try await HTTPClient.shared.get(
            "\(web)/x/v2/reply/wbi/main",
            query: params,
            as: CommentMainData.self
        )
    }

    /// 一级评论列表（老端点，兜底）。
    ///
    /// 免签、免登录，但服务端现在对未登录/低权重请求只回 **3 条**一级评论
    /// （`page.count` 仍是真实总数）。因此它只在 `replyMain` 失败时使用。
    ///
    /// `sort`: 0 按时间 / 2 按热度。
    func replyList(aid: Int, page: Int = 1, pageSize: Int = 20, sort: Int = 2) async throws -> CommentListData {
        try await HTTPClient.shared.get(
            "\(web)/x/v2/reply",
            query: [
                "type": "1",
                "oid": "\(aid)",
                "pn": "\(page)",
                "ps": "\(pageSize)",
                "sort": "\(sort)",
                "nohot": "1",
                "plat": "1",
                "web_location": "1315875"
            ],
            as: CommentListData.self
        )
    }

    /// 楼中楼。`root` 传一级评论的 rpid。
    func replyReplies(aid: Int, root: Int, page: Int = 1, pageSize: Int = 10) async throws -> CommentReplyData {
        try await HTTPClient.shared.get(
            "\(web)/x/v2/reply/reply",
            query: [
                "type": "1",
                "oid": "\(aid)",
                "root": "\(root)",
                "pn": "\(page)",
                "ps": "\(pageSize)",
                "plat": "1",
                "web_location": "333.790"
            ],
            as: CommentReplyData.self
        )
    }

    /// 发表评论 / 回复。
    ///
    /// - 一级评论：`root` 与 `parent` 都传 0
    /// - 楼中楼回复：`root` 传楼主的 rpid，`parent` 传被回复那条的 rpid
    ///
    /// 必须登录 + `csrf`（`HTTPClient` 统一注入）。
    func addReply(aid: Int, message: String, root: Int = 0, parent: Int = 0) async throws -> CommentAddData {
        try await HTTPClient.shared.post(
            "\(web)/x/v2/reply/add",
            form: [
                "oid": "\(aid)",
                "type": "1",
                "message": message,
                "root": "\(root)",
                "parent": "\(parent)",
                "plat": "1"
            ],
            as: CommentAddData.self
        )
    }

    /// 评论点赞 / 取消。`action`: 1 点赞 / 0 取消。
    func likeReply(aid: Int, rpid: Int, liked: Bool) async throws {
        try await HTTPClient.shared.postVoid(
            "\(web)/x/v2/reply/action",
            form: [
                "oid": "\(aid)",
                "type": "1",
                "rpid": "\(rpid)",
                "action": liked ? "1" : "0"
            ]
        )
    }

    // MARK: - 关注关系

    /// 是否已关注该 UP 主
    func isFollowing(mid: Int) async -> Bool? {
        guard let data = try? await HTTPClient.shared.get(
            "\(web)/x/relation",
            query: ["fid": "\(mid)"],
            as: RelationData.self
        ) else { return nil }
        guard let attribute = data.attribute else { return nil }
        return attribute == 2 || attribute == 6
    }

    /// act: 1 关注 / 2 取关
    func modifyRelation(mid: Int, follow: Bool) async throws {
        try await HTTPClient.shared.postVoid(
            "\(web)/x/relation/modify",
            form: [
                "fid": "\(mid)",
                "act": follow ? "1" : "2",
                "re_src": "11"
            ]
        )
    }

    // MARK: - 互动（点赞 / 投币 / 收藏）

    /// `has/like` 的 data 是裸数字 0/1，不是对象
    func hasLike(aid: Int) async -> Bool? {
        guard let value = try? await HTTPClient.shared.get(
            "\(web)/x/web-interface/archive/has/like",
            query: ["aid": "\(aid)"],
            as: Int.self
        ) else { return nil }
        return value == 1
    }

    /// 已投币枚数（0~2）
    func hasCoin(aid: Int) async -> Int? {
        try? await HTTPClient.shared.get(
            "\(web)/x/web-interface/archive/has/coin",
            query: ["aid": "\(aid)"],
            as: Int.self
        )
    }

    func isFavoured(aid: Int) async -> Bool? {
        guard let data = try? await HTTPClient.shared.get(
            "\(web)/x/v2/fav/video/favoured",
            query: ["aid": "\(aid)"],
            as: FavouredData.self
        ) else { return nil }
        return data.favoured
    }

    /// like: 1 点赞 / 2 取消
    func setLike(aid: Int, liked: Bool) async throws {
        try await HTTPClient.shared.postVoid(
            "\(web)/x/web-interface/archive/like",
            form: ["aid": "\(aid)", "like": liked ? "1" : "2"]
        )
    }

    func addCoin(aid: Int, count: Int = 1, alsoLike: Bool = false) async throws {
        try await HTTPClient.shared.postVoid(
            "\(web)/x/web-interface/coin/add",
            form: [
                "aid": "\(aid)",
                "multiply": "\(count)",
                "select_like": alsoLike ? "1" : "0"
            ]
        )
    }

    /// 收藏 / 取消收藏。
    /// 收藏必须落到具体收藏夹，因此先取一次默认收藏夹 id 并缓存。
    func setFavourite(aid: Int, favourite: Bool, ownerMid: Int?) async throws {
        if favourite {
            guard let folderID = await defaultFavFolderID(mid: ownerMid) else {
                throw BiliError.api(code: -1, message: "没有可用的收藏夹")
            }
            try await HTTPClient.shared.postVoid(
                "\(web)/x/v3/fav/resource/deal",
                form: [
                    "rid": "\(aid)",
                    "type": "2",
                    "add_media_ids": "\(folderID)",
                    "del_media_ids": ""
                ]
            )
        } else {
            let folders = await favFolderIDs(mid: ownerMid)
            try await HTTPClient.shared.postVoid(
                "\(web)/x/v3/fav/resource/deal",
                form: [
                    "rid": "\(aid)",
                    "type": "2",
                    "add_media_ids": "",
                    "del_media_ids": folders.map(String.init).joined(separator: ",")
                ]
            )
        }
    }

    /// 自己的收藏夹 id 列表
    func favFolderIDs(mid: Int?) async -> [Int] {
        guard let mid else { return [] }
        guard let data = try? await favFolders(mid: mid) else { return [] }
        return (data.list ?? []).map(\.id)
    }

    private var cachedDefaultFolderID: Int?
    private func defaultFavFolderID(mid: Int?) async -> Int? {
        if let cachedDefaultFolderID { return cachedDefaultFolderID }
        guard let first = await favFolderIDs(mid: mid).first else { return nil }
        cachedDefaultFolderID = first
        return first
    }

    // MARK: - 观看进度上报

    /// 心跳上报，让 B站的历史记录同步「看到哪」。
    /// 失败不影响本地续播，因此调用方一律 `try?`。
    func reportProgress(aid: Int, cid: Int, playedSeconds: Double) async throws {
        try await HTTPClient.shared.postVoid(
            "\(web)/x/click-interface/web/heartbeat",
            form: [
                "aid": "\(aid)",
                "cid": "\(cid)",
                "played_time": "\(Int(playedSeconds))",
                "realtime": "\(Int(playedSeconds))",
                "real_played_time": "\(Int(playedSeconds))",
                "start_ts": "\(Int(Date().timeIntervalSince1970))",
                "type": "3",
                "sub_type": "0",
                "dt": "2",
                "play_type": "0"
            ]
        )
    }

    // MARK: - 扫码登录

    func qrGenerate() async throws -> QRGenerateData {
        try await HTTPClient.shared.get(
            "\(passport)/x/passport-login/web/qrcode/generate",
            query: ["source": "main-fe-header", "go_url": "https://www.bilibili.com"],
            as: QRGenerateData.self,
            referer: "https://www.bilibili.com",
            withCookies: false
        )
    }

    /// 轮询扫码状态。登录成功时凭证通过 Set-Cookie 下发，由 CookieJar 自动吸收。
    func qrPoll(qrcodeKey: String) async throws -> QRPollData {
        try await HTTPClient.shared.get(
            "\(passport)/x/passport-login/web/qrcode/poll",
            query: ["qrcode_key": qrcodeKey],
            as: QRPollData.self,
            referer: "https://www.bilibili.com",
            withCookies: false
        )
    }

    // MARK: - WBI

    private func mixinKey(force: Bool = false) async throws -> String {
        if !force,
           let key = cachedMixinKey,
           let at = mixinKeyFetchedAt,
           Date().timeIntervalSince(at) < mixinKeyTTL {
            return key
        }
        guard let navInfo = await nav(), let wbi = navInfo.wbiImg else {
            throw BiliError.api(code: -101, message: "无法获取 WBI 密钥")
        }
        let key = WBISigner.mixinKey(imgURL: wbi.imgUrl, subURL: wbi.subUrl)
        cachedMixinKey = key
        mixinKeyFetchedAt = Date()
        return key
    }
}
