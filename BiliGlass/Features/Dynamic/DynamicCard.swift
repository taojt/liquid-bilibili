import SwiftUI

/// 动态时间线里的一条。
///
/// 布局分三段：作者行（头像/昵称可点进 UP 主页）、正文（可选）、投稿卡片（可选）。
/// 头部的 UP 链接和投稿卡片是两个**平级**的 NavigationLink，
/// 不做嵌套——SwiftUI 里 NavigationLink 套 NavigationLink 会互相抢手势。
struct DynamicCard: View {
    let cell: DynamicCell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let text = cell.text {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .lineSpacing(3)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let bvid = cell.bvid, !bvid.isEmpty {
                NavigationLink {
                    VideoDetailView(bvid: bvid, fallbackTitle: cell.title ?? "")
                } label: {
                    archiveCard
                }
                .buttonStyle(.cardPress)
            }

            statRow
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - 作者行

    private var header: some View {
        HStack(spacing: 9) {
            NavigationLink {
                if let mid = cell.authorMid {
                    UserSpaceView(mid: mid, fallbackName: cell.authorName, fallbackFace: cell.authorFace)
                } else {
                    EmptyView()
                }
            } label: {
                HStack(spacing: 9) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let action = cell.action, !action.isEmpty {
                            Text(action)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.liquidPress)
            .disabled(cell.authorMid == nil)

            Spacer(minLength: 0)

            Text(cell.publishedText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private var avatar: some View {
        AsyncImage(url: (cell.authorFace ?? "").biliImageURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .glassSurface(.regular.tint(Theme.purple.opacity(0.7)), in: .circle)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(.circle)
    }

    // MARK: - 投稿卡片

    private var archiveCard: some View {
        HStack(spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 5) {
                Text(cell.title ?? "")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let play = cell.playText, !play.isEmpty {
                        Label(play, systemImage: "play.fill")
                    }
                    if let danmaku = cell.danmakuText, !danmaku.isEmpty {
                        Label(danmaku, systemImage: "text.bubble.fill")
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.inkFaint)
            }
            .frame(height: 74, alignment: .top)
        }
        .padding(8)
        .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.6)
        }
    }

    private var cover: some View {
        Color.clear
            .frame(width: 116, height: 74)
            .overlay {
                AsyncImage(
                    url: (cell.cover ?? "").biliThumbnail(width: 320),
                    transaction: .init(animation: .easeOut(duration: 0.2))
                ) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.glow(for: cell.id))
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if cell.duration > 0 {
                    Text(cell.duration.durationText)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(4)
                }
            }
    }

    // MARK: - 互动数

    private var statRow: some View {
        HStack(spacing: 16) {
            if let likes = cell.likeCount {
                Label(likes.biliCount, systemImage: "hand.thumbsup")
            }
            if let comments = cell.commentCount {
                Label(comments.biliCount, systemImage: "bubble.left")
            }
            if let forwards = cell.forwardCount {
                Label(forwards.biliCount, systemImage: "arrowshape.turn.up.right")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.inkFaint)
    }
}
