import SwiftUI

/// 单条评论（一级评论与楼中楼共用）。
///
/// 层级差异只体现在缩进、头像尺寸与字号上，交互逻辑完全一致：
/// 头像/昵称进个人主页、点赞、回复。
struct CommentRowView: View {
    let comment: BiliComment
    /// 只有一级评论才有 Thread（楼中楼没有进一步展开）
    var thread: CommentService.Thread?
    let service: CommentService
    var depth: Int = 0
    /// UP 主 mid，用于打「UP主」标签
    var upMid: Int = 0
    /// 置顶评论额外打一个标签
    var pinned: Bool = false
    var onReply: (BiliComment) -> Void

    private var isUp: Bool { upMid != 0 && comment.mid == upMid }
    private var isNested: Bool { depth > 0 }
    private var avatarSize: CGFloat { isNested ? 24 : 34 }
    private var textSize: CGFloat { isNested ? 12.5 : 13.5 }

    var body: some View {
        HStack(alignment: .top, spacing: isNested ? 8 : 10) {
            avatarLink

            VStack(alignment: .leading, spacing: 5) {
                header
                message
                footer
                if !isNested { repliesBlock }
            }
        }
        .padding(.vertical, isNested ? 7 : 11)
    }

    // MARK: - 头部：昵称 + 等级 + 点赞

    private var header: some View {
        HStack(spacing: 5) {
            if pinned {
                Text("置顶")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Theme.blue.opacity(0.16), in: .capsule)
            }
            nameLink
            levelBadge
            if isUp {
                Text("UP主")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.pink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Theme.pink.opacity(0.16), in: .capsule)
            }
            Spacer(minLength: 4)
            likeButton
        }
    }

    private var nameLink: some View {
        NavigationLink {
            UserSpaceView(
                mid: comment.member.mid,
                fallbackName: comment.member.name,
                fallbackFace: comment.member.avatar
            )
        } label: {
            HStack(spacing: 4) {
                Text(comment.member.name)
                    .font(.system(size: isNested ? 11.5 : 12.5, weight: .medium))
                    .foregroundStyle(comment.member.mid == 0 ? Theme.inkFaint : Theme.inkDim)
                    .lineLimit(1)
                if comment.member.vipType > 0 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.pink)
                }
            }
        }
        .buttonStyle(.liquidPress)
        .disabled(comment.member.mid == 0)
    }

    /// LV 徽章：B站的等级是 0~6，0 级（新号）不显示，避免满屏 LV0
    @ViewBuilder
    private var levelBadge: some View {
        if comment.member.level > 0 {
            Text("LV\(comment.member.level)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.pink.opacity(0.9))
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1)
                .overlay {
                    Capsule().strokeBorder(Theme.pink.opacity(0.45), lineWidth: 0.6)
                }
        }
    }

    private var likeButton: some View {
        let state = service.likeState(for: comment)
        return Button {
            Task { await service.toggleLike(comment: comment) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: state.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 10.5, weight: .semibold))
                if state.count > 0 {
                    Text(state.count.biliCount)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(state.liked ? Theme.pink : Theme.inkFaint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.liquidPress)
    }

    // MARK: - 正文

    private var message: some View {
        Text(comment.message)
            .font(.system(size: textSize))
            .foregroundStyle(Theme.ink.opacity(0.9))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 底部：时间 + 回复

    private var footer: some View {
        HStack(spacing: 12) {
            Text(comment.ctime.relativeTimeText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)

            Button {
                onReply(comment)
            } label: {
                Text("回复")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .contentShape(.rect)
            }
            .buttonStyle(.liquidPress)
        }
    }

    // MARK: - 楼中楼

    @ViewBuilder
    private var repliesBlock: some View {
        if let thread, comment.rcount > 0 || !thread.replies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                let visible = thread.visibleReplies
                ForEach(visible) { reply in
                    CommentRowView(
                        comment: reply,
                        thread: nil,
                        service: service,
                        depth: depth + 1,
                        upMid: upMid,
                        onReply: onReply
                    )
                }

                if thread.expanded {
                    HStack(spacing: 14) {
                        if thread.hasMoreReplies {
                            Button {
                                Task { await service.loadMoreReplies(threadID: thread.id) }
                            } label: {
                                Text("展开更多回复")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.blue)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.liquidPress)
                        }
                        Button {
                            Task { await service.toggleReplies(threadID: thread.id) }
                        } label: {
                            Text("收起")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.liquidPress)
                    }
                } else {
                    Button {
                        Task { await service.toggleReplies(threadID: thread.id) }
                    } label: {
                        HStack(spacing: 3) {
                            Text(replySummary(thread))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.blue)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.liquidPress)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.top, 2)
            .overlay(alignment: .leading) {
                // 一条细竖线明确「这些是回复」，比纯粹缩进更清楚
                Rectangle()
                    .fill(Theme.ink.opacity(0.10))
                    .frame(width: 1.5)
            }
        }
    }

    private func replySummary(_ thread: CommentService.Thread) -> String {
        let shown = thread.visibleReplies.count
        if thread.comment.rcount > shown {
            return "共 \(thread.comment.rcount) 条回复"
        }
        return "展开 \(thread.comment.rcount) 条回复"
    }

    // MARK: - 头像

    private var avatarLink: some View {
        NavigationLink {
            UserSpaceView(
                mid: comment.member.mid,
                fallbackName: comment.member.name,
                fallbackFace: comment.member.avatar
            )
        } label: {
            avatar
        }
        .buttonStyle(.liquidPress)
        .disabled(comment.member.mid == 0)
    }

    private var avatar: some View {
        AsyncImage(url: comment.member.avatar.biliImageURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(Theme.ink.opacity(0.10))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: avatarSize * 0.42))
                            .foregroundStyle(Theme.inkFaint)
                    }
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.5)
        }
    }
}
