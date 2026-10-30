import SwiftUI

/// 双列网格里的视频卡片。
///
/// 造型向 Apple TV 靠：**封面就是卡片本体**，不再给整张卡片套一层玻璃底——
/// 一格一格全是玻璃的话，页面会变成一片磨砂，反而不见"玻璃"。
/// 把玻璃让给悬浮栏、角标、按钮这些真正该浮起来的层，封面上只留
/// 一道极细的受光边和柔投影，剩下的对比度全交给封面本身。
///
/// 卡片本身不带交互，点击行为由外层的 NavigationLink 决定。
struct VideoGridCard: View {
    let model: VideoCellModel

    private var coverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverView

            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                footer
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 封面

    private var coverView: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(
                    url: model.cover.biliThumbnail(width: 480),
                    transaction: .init(animation: .easeOut(duration: 0.25))
                ) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.glow(for: model.id))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // 底部压暗，让角标在任何封面上都读得清
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 44)
                .allowsHitTesting(false)
            }
            .clipShape(coverShape)
            .liquidEdge(coverShape, lineWidth: 0.9)
            .shadow(color: .black.opacity(0.32), radius: 9, y: 5)
            .overlay(alignment: .bottomLeading) { statsBadge }
            .overlay(alignment: .bottomTrailing) { durationBadge }
            .overlay(alignment: .bottom) { progressBar }
    }

    private var statsBadge: some View {
        HStack(spacing: 6) {
            if let view = model.viewCount {
                Label(view.biliCount, systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            if let danmaku = model.danmakuCount {
                Label(danmaku.biliCount, systemImage: "text.bubble.fill")
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .glassSurface(.regular, in: .capsule)
        .liquidEdge(Capsule(style: .continuous), lineWidth: 0.7)
        .padding(7)
    }

    private var durationBadge: some View {
        GlassTag(text: model.progressText ?? model.duration.durationText)
            .padding(7)
    }

    /// 历史记录的续播进度
    @ViewBuilder
    private var progressBar: some View {
        if let ratio = model.progressRatio {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.pink, Theme.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * ratio)
                        .shadow(color: Theme.pink.opacity(0.6), radius: 4)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - 底部信息

    private var footer: some View {
        HStack(spacing: 5) {
            if let face = model.upFace, let url = face.biliImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Theme.ink.opacity(0.15))
                }
                .frame(width: 15, height: 15)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.inkFaint.opacity(0.55))
                    .frame(width: 15, height: 15)
                    .background(Theme.ink.opacity(0.1), in: .circle)
            }

            Text(model.upName ?? "未知UP主")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkDim.opacity(0.62))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 展示辅助

extension VideoCellModel {
    /// 历史记录显示"看到 12:34"，普通视频不显示
    var progressText: String? {
        guard let progress, progress > 0 else { return nil }
        return "看到 \(progress.durationText)"
    }

    /// 发布时间相对描述
    var publishedText: String? {
        guard let publishedAt, publishedAt > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(publishedAt))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 {
            formatter.dateFormat = "HH:mm"
        } else if days < 365 {
            formatter.dateFormat = "MM-dd"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }
}
