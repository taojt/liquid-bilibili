import Foundation

/// 评论列表 / 子回复共用的分页信息。
///
/// 注意 `count` 在列表接口里是**一级评论总数**，在子回复接口里是**该楼的回复总数**，
/// 语义不同但字段名一样，所以只做透传，由调用方各自解释。
struct CommentPageInfo: Decodable {
    let count: Int?
    let num: Int?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case count, num, size
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.flexibleInt(.count)
        num = c.flexibleInt(.num)
        size = c.flexibleInt(.size)
    }
}

/// 评论作者。
///
/// `mid` 在 `member` 里是**字符串**（`"18211317"`），而评论体本身的 `mid` 是数字，
/// 两个都要吃，统一在转换层压平成 Int。
struct CommentMember: Decodable {
    let mid: Int
    let name: String
    let avatar: String
    let level: Int
    /// 大会员类型，非 0 显示粉色角标
    let vipType: Int

    enum CodingKeys: String, CodingKey {
        case mid, uname, avatar, level_info, vip
    }

    private enum LevelKeys: String, CodingKey {
        case current_level
    }

    private enum VipKeys: String, CodingKey {
        case vipType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mid = c.flexibleInt(.mid) ?? 0
        name = c.flexibleString(.uname) ?? "匿名用户"

        // 头像可能是 // 开头或 http://，交给 biliImageURL 统一改写
        let raw = c.flexibleString(.avatar) ?? ""
        avatar = raw.hasPrefix("//") ? "https:" + raw : raw

        let levelBox = try? c.nestedContainer(keyedBy: LevelKeys.self, forKey: .level_info)
        level = levelBox?.flexibleInt(.current_level) ?? 0

        let vipBox = try? c.nestedContainer(keyedBy: VipKeys.self, forKey: .vip)
        vipType = vipBox?.flexibleInt(.vipType) ?? 0
    }
}

/// 评论正文。图片 / 表情 / @ 跳转一律只取纯文本，
/// `message` 里保留了 `[笑]` 这类表情占位符，原样展示即可。
struct CommentContent: Decodable {
    let message: String

    enum CodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = (c.flexibleString(.message) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 单条评论（一级评论与楼中楼共用同一结构）。
struct BiliComment: Decodable, Identifiable {
    let rpid: Int
    let mid: Int
    /// 一级评论为 0；楼中楼指向所属的根评论 rpid
    let root: Int
    /// 楼中楼指向被回复的那条 rpid
    let parent: Int
    let ctime: Int
    let like: Int
    /// 子回复总数
    let rcount: Int
    /// 当前登录用户是否已点赞（0 / 1）
    let liked: Bool
    let member: CommentMember
    let message: String
    /// 接口偶尔会在列表里带 2~3 条预览回复
    let previewReplies: [BiliComment]

    var id: Int { rpid }
    var isRoot: Bool { root == 0 }

    enum CodingKeys: String, CodingKey {
        case rpid, mid, root, parent, ctime, like, rcount, action
        case member, content, replies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpid = c.flexibleInt(.rpid) ?? 0
        mid = c.flexibleInt(.mid) ?? 0
        root = c.flexibleInt(.root) ?? 0
        parent = c.flexibleInt(.parent) ?? 0
        ctime = c.flexibleInt(.ctime) ?? 0
        like = c.flexibleInt(.like) ?? 0
        rcount = c.flexibleInt(.rcount) ?? 0
        liked = (c.flexibleInt(.action) ?? 0) == 1
        member = (try? c.decode(CommentMember.self, forKey: .member)) ?? CommentMember.empty
        message = (try? c.decode(CommentContent.self, forKey: .content))?.message ?? ""
        let preview = (try? c.decodeIfPresent([BiliComment].self, forKey: .replies)) ?? nil
        previewReplies = preview ?? []
    }
}

extension CommentMember {
    /// 评论被删/被折叠时 `member` 可能整体缺失，给一个占位避免整条评论丢失
    static let empty = CommentMember(placeholder: ())
}

extension CommentMember {
    init(placeholder: ()) {
        mid = 0
        name = "已注销用户"
        avatar = ""
        level = 0
        vipType = 0
    }
}

/// 网页端正式接口 `x/v2/reply/wbi/main` 的游标。
///
/// 翻页靠 `pagination_reply.next_offset`（一串 base64 样子的游标），
/// 而不是页码；`next_offset` 偶尔是空串，此时退回 `pagination_str.offset`。
/// 两者都没有就说明到底了。
struct CommentCursor: Decodable {
    let isEnd: Bool
    let allCount: Int
    let nextOffset: String

    enum CodingKeys: String, CodingKey {
        case is_end, all_count, pagination_reply, pagination_str
    }

    private enum ReplyKeys: String, CodingKey {
        case next_offset
    }

    private enum StrKeys: String, CodingKey {
        case offset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnd = c.flexibleBool(.is_end) ?? true
        allCount = c.flexibleInt(.all_count) ?? 0

        var offset = ""
        if let box = try? c.nestedContainer(keyedBy: ReplyKeys.self, forKey: .pagination_reply) {
            offset = box.flexibleString(.next_offset) ?? ""
        }
        if offset.isEmpty,
           let box = try? c.nestedContainer(keyedBy: StrKeys.self, forKey: .pagination_str) {
            offset = box.flexibleString(.offset) ?? ""
        }
        nextOffset = offset
    }
}

/// 一级评论列表（wbi/main）。
struct CommentMainData: Decodable {
    let replies: [BiliComment]
    let topReplies: [BiliComment]
    let cursor: CommentCursor?

    enum CodingKeys: String, CodingKey {
        case replies, cursor
        case top_replies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = (try? c.decodeIfPresent([BiliComment].self, forKey: .replies)) ?? nil
        replies = list ?? []
        let pinned = (try? c.decodeIfPresent([BiliComment].self, forKey: .top_replies)) ?? nil
        topReplies = pinned ?? []
        cursor = (try? c.decodeIfPresent(CommentCursor.self, forKey: .cursor)) ?? nil
    }
}

/// 一级评论列表（老接口，兜底用）。
///
/// `top` 是 UP 主置顶（可能为空），与 `replies` 分开放；
/// 展示时置顶排在正常列表之前。
struct CommentListData: Decodable {
    let replies: [BiliComment]
    let top: [BiliComment]
    let page: CommentPageInfo?

    enum CodingKeys: String, CodingKey {
        case replies, top, page
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = (try? c.decodeIfPresent([BiliComment].self, forKey: .replies)) ?? nil
        replies = list ?? []
        let pinned = (try? c.decodeIfPresent([BiliComment].self, forKey: .top)) ?? nil
        top = pinned ?? []
        page = (try? c.decodeIfPresent(CommentPageInfo.self, forKey: .page)) ?? nil
    }
}

/// 楼中楼分页。结构与一级列表相同，`top` 恒为空。
struct CommentReplyData: Decodable {
    let replies: [BiliComment]
    let page: CommentPageInfo?

    enum CodingKeys: String, CodingKey {
        case replies, page
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = (try? c.decodeIfPresent([BiliComment].self, forKey: .replies)) ?? nil
        replies = list ?? []
        page = (try? c.decodeIfPresent(CommentPageInfo.self, forKey: .page)) ?? nil
    }
}

/// 发表评论后返回的凭证。只用到 `rpid`，其余字段留着便于排查。
struct CommentAddData: Decodable {
    let rpid: Int

    enum CodingKeys: String, CodingKey {
        case rpid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpid = c.flexibleInt(.rpid) ?? 0
    }
}

/// 排序方式。
///
/// 两套接口用的取值不一样，必须分别映射：
/// - 老接口 `x/v2/reply`：0 按时间 / 2 按热度
/// - 正式接口 `wbi/main`：2 按时间 / 3 按热度
enum CommentSort: Int, CaseIterable, Identifiable {
    case hot = 2
    case newest = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hot: return "按热度"
        case .newest: return "按时间"
        }
    }

    /// 老接口的 sort 参数
    var legacyValue: Int { rawValue }

    /// wbi/main 的 mode 参数
    var mainMode: Int {
        switch self {
        case .hot: return 3
        case .newest: return 2
        }
    }
}
