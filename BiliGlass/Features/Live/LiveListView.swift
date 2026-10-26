import SwiftUI

/// 直播二级页：双列直播卡片。
///
/// 拉流用 HLS（m3u8），AVPlayer 原生支持，不需要自研解码。
struct LiveListView: View {
    /// 纵向滚动偏移回调，与 VideoFeedGrid 一致，供首页顶栏做收起动画
    var onScroll: ((CGFloat) -> Void)? = nil

    @State private var rooms: [LiveRoom] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    /// 正在看的直播间。直播页要整屏铺满，所以用 fullScreenCover 而不是压栈，
    /// 否则会嵌在首页的 segmented 区域里，横屏时上面还露着首页的顶栏。
    @State private var playing: LiveRoom?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        list
            .fullScreenCover(item: $playing) { room in
                LivePlayerView(room: room)
            }
    }

    private var list: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 8)
                .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            onScroll?(offset)
        }
        .refreshable { await reload() }
        .task {
            if let id = DebugEntry.liveRoom {
                playing = LiveRoom(
                    roomid: id,
                    title: "调试直播间 \(id)",
                    cover: nil,
                    uname: "调试",
                    face: nil,
                    online: nil,
                    areaName: "调试"
                )
                return
            }
            guard !hasLoaded else { return }
            await load()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if rooms.isEmpty {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.pink)
                    Text("正在加载直播…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 110)
            } else if let error = errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.inkDim)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkDim)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await reload() } }
                        .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 90)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(rooms) { room in
                    Button {
                        playing = room
                    } label: {
                        LiveCard(room: room)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if room.id == rooms.last?.id, hasMore, !isLoading {
                            await load()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 数据

    private func reload() async {
        page = 1
        hasMore = true
        rooms = []
        errorMessage = nil
        await load()
    }

    private func load() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fresh = try await BiliAPI.shared.liveList(page: page)
            let existing = Set(rooms.map(\.id))
            rooms.append(contentsOf: fresh.filter { !existing.contains($0.id) })
            hasMore = !fresh.isEmpty
            page += 1
            // 只有真的拿到数据才算「加载过」。否则 .task 被取消后
            // hasLoaded 已置位，下次进页面会直接跳过、永远白屏。
            hasLoaded = true
        } catch {
            // 取消不是网络故障，不该弹错误，也不该封掉分页
            if !error.isCancellation {
                errorMessage = error.localizedDescription
                hasMore = false
            }
        }
        isLoading = false
    }
}

// MARK: - 直播卡片

struct LiveCard: View {
    let room: LiveRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover
            Text(room.title ?? "未命名直播间")
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

    private var cover: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: (room.cover ?? "").biliThumbnail(width: 480)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.glow(for: room.title ?? "live"))
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 13))
            .overlay(alignment: .topLeading) { liveBadge }
            .overlay(alignment: .bottomTrailing) { onlineBadge }
    }

    private var liveBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.white)
                .frame(width: 3.5, height: 3.5)
            Text("直播中")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.pink, in: .capsule)
        .padding(5)
    }

    private var onlineBadge: some View {
        Label((room.online ?? 0).biliCount, systemImage: "person.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .padding(5)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let face = room.face, let url = face.biliImageURL {
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

            Text(room.uname ?? "未知主播")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkDim)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let area = room.areaName {
                Text(area)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
            }
        }
    }
}
