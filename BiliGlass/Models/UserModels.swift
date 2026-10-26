import Foundation

// MARK: - UP 主名片

/// `x/web-interface/card` 的返回。
/// 这个端点免签、未登录也能用，是拿 UP 主资料最稳的一条路
/// （`x/space/wbi/acc/info` 现在动不动就 -352 风控）。
struct UserCardData: Decodable {
    let card: UserCard?
    let following: Bool?
    let archiveCount: Int?
    let follower: Int?
    let likeNum: Int?

    enum CodingKeys: String, CodingKey {
        case card, following, follower
        case archiveCount = "archive_count"
        case likeNum = "like_num"
    }
}

struct UserCard: Decodable, Hashable {
    let mid: Int
    let name: String
    let face: String
    let sign: String?
    let level: Int

    enum CodingKeys: String, CodingKey {
        case mid, name, face, sign
        case levelInfo = "level_info"
    }

    struct LevelInfo: Decodable, Hashable {
        let currentLevel: Int?

        enum CodingKeys: String, CodingKey {
            case currentLevel = "current_level"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 这个接口里 mid 是字符串，别处可能是数字，两种都吃
        if let number = try? c.decode(Int.self, forKey: .mid) {
            mid = number
        } else {
            let text = (try? c.decode(String.self, forKey: .mid)) ?? "0"
            mid = Int(text) ?? 0
        }
        name = (try? c.decode(String.self, forKey: .name)) ?? "未知UP主"
        face = (try? c.decode(String.self, forKey: .face)) ?? ""
        sign = (try? c.decodeIfPresent(String.self, forKey: .sign)) ?? nil
        let info = (try? c.decodeIfPresent(LevelInfo.self, forKey: .levelInfo)) ?? nil
        level = info?.currentLevel ?? 0
    }
}

// MARK: - UP 主投稿列表

/// `x/series/recArchivesByKeywords`（免签，首选）
struct SpaceArchiveData: Decodable {
    let archives: [SpaceArchive]?
    let page: SpacePage?
}

/// `x/space/wbi/arc/search`（需签名 + 登录，兜底）
struct SpaceArcSearchData: Decodable {
    let list: SpaceArcList?
    let page: SpaceArcPage?
}

struct SpaceArcList: Decodable {
    let vlist: [SpaceArcItem]?
}

struct SpaceArcPage: Decodable {
    let count: Int?
    let pn: Int?
    let ps: Int?
}

struct SpaceArcItem: Decodable {
    let aid: Int?
    let bvid: String?
    let title: String?
    let pic: String?
    /// "12:34"，注意是字符串
    let length: String?
    let play: Int?
    let comment: Int?
    let created: Int?
    let author: String?
}

struct SpacePage: Decodable {
    let num: Int?
    let size: Int?
    let total: Int?
}

/// 两个投稿接口字段名不同（duration/Int vs length/String），
/// 压平成同一个结构，页面只认这一种。
struct SpaceArchive: Decodable, Identifiable, Hashable {
    let aid: Int
    let bvid: String
    let title: String
    let cover: String
    let duration: Int
    let play: Int?
    let danmaku: Int?
    let publishedAt: Int?
    /// 视频作者。投稿列表里就是当前 UP 主（可缺省），
    /// 但「点赞过的视频」必须靠它区分作者，不能拿页面归属人顶替。
    let ownerName: String?
    let ownerFace: String?

    var id: String { bvid }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, duration, pubdate, stat, play, comment, created, length
        case owner
    }

    private struct Stat: Decodable { let view: Int?; let danmaku: Int? }
    private struct Owner: Decodable { let name: String?; let face: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aid = (try? c.decode(Int.self, forKey: .aid)) ?? 0
        bvid = (try? c.decode(String.self, forKey: .bvid)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        cover = (try? c.decode(String.self, forKey: .pic)) ?? ""

        // recArchivesByKeywords: duration 是秒；arc/search: length 是 "12:34"
        if let seconds = try? c.decode(Int.self, forKey: .duration) {
            duration = seconds
        } else {
            let text = (try? c.decode(String.self, forKey: .length)) ?? ""
            let parts = text.split(separator: ":").compactMap { Int($0) }
            switch parts.count {
            case 2: duration = parts[0] * 60 + parts[1]
            case 3: duration = parts[0] * 3600 + parts[1] * 60 + parts[2]
            default: duration = 0
            }
        }

        let statBox = (try? c.decodeIfPresent(Stat.self, forKey: .stat)) ?? nil
        play = statBox?.view ?? (try? c.decode(Int.self, forKey: .play))
        danmaku = statBox?.danmaku ?? (try? c.decode(Int.self, forKey: .comment))
        let published = (try? c.decodeIfPresent(Int.self, forKey: .pubdate)) ?? nil
        let created = (try? c.decodeIfPresent(Int.self, forKey: .created)) ?? nil
        publishedAt = published ?? created

        let ownerBox = (try? c.decodeIfPresent(Owner.self, forKey: .owner)) ?? nil
        ownerName = ownerBox?.name
        ownerFace = ownerBox?.face
    }

    /// `arc/search` 的 vlist 条目
    init(arcItem: SpaceArcItem) {
        aid = arcItem.aid ?? 0
        bvid = arcItem.bvid ?? ""
        title = arcItem.title ?? ""
        cover = arcItem.pic ?? ""
        let parts = (arcItem.length ?? "").split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: duration = parts[0] * 60 + parts[1]
        case 3: duration = parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: duration = 0
        }
        play = arcItem.play
        danmaku = arcItem.comment
        publishedAt = arcItem.created
        ownerName = arcItem.author
        ownerFace = nil
    }

    /// 转成网格卡片使用的统一模型。
    /// `arc/search` 与 `recArchivesByKeywords` 都不带 UP 主信息，
    /// 因此在 UP 主页里由调用方把当前 UP 的名字/头像补进去。
    func cellModel(upName: String? = nil, upFace: String? = nil) -> VideoCellModel {
        VideoCellModel(
            id: bvid,
            title: title,
            cover: cover,
            duration: duration,
            upName: ownerName ?? upName,
            upFace: ownerFace ?? upFace,
            viewCount: play,
            danmakuCount: danmaku,
            publishedAt: publishedAt
        )
    }
}

/// 投稿列表的一页
struct UserArchivePage: Sendable {
    let items: [SpaceArchive]
    let hasMore: Bool
}

// MARK: - 互动状态

struct FavouredData: Decodable {
    let count: Int?
    let favoured: Bool?
}

struct RelationData: Decodable {
    /// 0 未关注 / 2 已关注 / 6 互关 / 128 拉黑
    let attribute: Int?
}
