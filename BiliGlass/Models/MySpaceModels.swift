import Foundation

// MARK: - 我的资料

/// `x/space/myinfo`：仅登录态可用，比 `card` 多出硬币、生日、等级等「账号属性」。
/// 字段在各灰度版本里类型不稳（`coins` 有时是 Double，`level` 有时是 Int），
/// 因此全部走宽松解码，缺字段不影响整页。
struct MyInfoData: Decodable {
    let mid: Int?
    let name: String?
    let sign: String?
    let level: Int?
    let sex: String?
    let face: String?
    /// 硬币数，接口给的是小数（如 123.4），展示时取整
    let coins: Double?
    /// 生日，秒级时间戳；0 表示未设置
    let birthday: Int?

    enum CodingKeys: String, CodingKey {
        case mid, name, sign, level, sex, face, coins, birthday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mid = c.flexibleInt(.mid)
        name = c.flexibleString(.name)
        sign = c.flexibleString(.sign)
        level = c.flexibleInt(.level)
        sex = c.flexibleString(.sex)
        face = c.flexibleString(.face)
        coins = (try? c.decodeIfPresent(Double.self, forKey: .coins)) ?? nil
        birthday = c.flexibleInt(.birthday)
    }
}

// MARK: - 关注 / 粉丝

/// `x/relation/stat?vmid=`：免签、未登录也能查，因此「我的主页」与「UP 主页」共用。
struct RelationStatData: Decodable {
    let following: Int?
    let follower: Int?

    enum CodingKeys: String, CodingKey {
        case following, follower
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        following = c.flexibleInt(.following)
        follower = c.flexibleInt(.follower)
    }
}

// MARK: - 点赞过的视频

/// `x/space/like/video?vmid=`：条目结构与投稿列表一致，
/// 直接复用 `SpaceArchive`（`stat.view` / `pubdate` / `duration` 都在）。
struct LikeVideoData: Decodable {
    let count: Int?
    let list: [SpaceArchive]?

    enum CodingKeys: String, CodingKey {
        case count, list
    }
}
