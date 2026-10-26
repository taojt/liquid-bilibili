import SwiftUI

/// 双列网格里的视频卡片。
///
/// 封面上的角标（时长、播放量）用玻璃胶囊压在图片上，卡片整体也带一层玻璃底，
/// 这样既能折射出封面内容，又保证深色背景下的文字可读性。
/// 卡片本身不带交互，点击行为由外层的 NavigationLink 决定。
struct VideoGridCard: View {
    let model: VideoCellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            coverView

            Text(model.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            footer
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
            .clipShape(.rect(cornerRadius: 13))
            .overlay(alignment: .bottomLeading) { statsBadge }
            .overlay(alignment: .bottomTrailing) { durationBadge }
            .overlay(alignment: .bottom) { progressBar }
    }

    private var statsBadge: some View {
        HStack(spacing: 4) {
            if let view = model.viewCount {
                Label(view.biliCount, systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            if let danmaku = model.danmakuCount {
                Label(danmaku.biliCount, systemImage: "text.bubble.fill")
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
        .padding(5)
    }

    private var durationBadge: some View {
        Text(model.progressText ?? model.duration.durationText)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .padding(5)
    }

    /// 历史记录的续播进度
    @ViewBuilder
    private var progressBar: some View {
        if let ratio = model.progressRatio {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(Theme.pink)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 2.5)
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
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
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 15, height: 15)
                    .background(Theme.ink.opacity(0.1), in: .circle)
            }

            Text(model.upName ?? "未知UP主")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkDim)
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
