import SwiftUI
import AVFoundation
import UIKit

/// 直播间播放页。
///
/// B站直播下发的是 HLS（m3u8）地址，AVPlayer 原生就能播，
/// 不需要自研 FLV 解码器，因此这里是整条链路里最短的一条。
///
/// 画面与弹幕是两条**独立**的链路：
/// - 画面：HTTP 拉流，链路在播放器内部，我们只负责给地址；
/// - 弹幕：WebSocket 长连接，由 `LiveDanmakuClient` 维护，与画面没有任何时序耦合。
///
/// 因此弹幕不会跟着「视频缓冲」走，也不会受倍速影响——直播本来就只有 1 倍速。
struct LivePlayerView: View {
    let room: LiveRoom

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// 弹幕长连接。生命周期跟着这个页面走，关掉就断。
    @State private var danmaku = LiveDanmakuClient()
    @State private var showDanmaku = true

    @State private var isFullscreen = false
    @State private var controlsVisible = true
    @State private var autoHideTask: Task<Void, Never>?
    @State private var showDanmakuSettings = false

    private var danmakuSettings: DanmakuSettings { DanmakuSettings.shared }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            }

            danmakuLayer

            if isLoading {
                loadingCard
            } else if let errorMessage {
                errorCard(errorMessage)
            }

            controlsLayer
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // fullScreenCover 理论上会盖住悬浮底栏，这里再登记一道，万一
        // 呈现层带透明背景时底栏也不会透出来
        .hidesFloatingTabBar()
        .statusBarHidden(isFullscreen)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .task { await start() }
        .onAppear {
            // 驻留期间放开旋转，手机转横屏就自动进全屏
            OrientationLock.allowRotation()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            // 看直播不应该息屏
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleAutoHide()
            if DebugEntry.fullscreen {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    toggleFullscreen()
                }
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
            autoHideTask = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            OrientationLock.lockPortrait()
            UIApplication.shared.isIdleTimerDisabled = false
            player?.pause()
            danmaku.disconnect()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncWithDeviceOrientation()
        }
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsSheet()
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
                .onDisappear { controlsVisible = true }
        }
    }

    // MARK: - 弹幕层

    private var danmakuLayer: some View {
        Group {
            if showDanmaku, !danmaku.bullets.isEmpty {
                LiveDanmakuOverlay(
                    bullets: danmaku.bullets,
                    startedAt: danmaku.sessionStartedAt,
                    fontSize: isFullscreen ? 17 : 13,
                    topInset: danmakuTopInset,
                    opacity: danmakuSettings.opacity,
                    area: danmakuSettings.area
                )
                .ignoresSafeArea()
            }
        }
    }

    /// 顶部给玻璃控制条让出的高度。
    ///
    /// **不随控制条显隐变化**——一变轨道数量就重排，屏幕上的弹幕会整体跳一下。
    /// 宁可让控制条隐藏后上方空一块，也不让弹幕抖。
    private var danmakuTopInset: CGFloat {
        isFullscreen ? 66 : 122
    }

    // MARK: - 控制层

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if !isFullscreen { footer }
        }
        .opacity(controlsVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .allowsHitTesting(controlsVisible)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "chevron.left", size: 38) { close() }

            VStack(alignment: .leading, spacing: 1) {
                Text(room.title ?? "直播间")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(room.uname ?? "未知主播") · \(room.areaName ?? "直播")")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkDim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassSurface(.regular, in: .capsule)

            Spacer(minLength: 0)

            liveBadge

            GlassIconButton(
                systemName: showDanmaku ? "text.bubble.fill" : "text.bubble",
                size: 38,
                tint: showDanmaku ? Theme.pink.opacity(0.55) : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showDanmaku.toggle() }
                scheduleAutoHide()
            }

            GlassIconButton(
                systemName: "slider.horizontal.3",
                size: 38,
                tint: danmakuSettings.isDefault ? nil : Theme.pink.opacity(0.45)
            ) {
                autoHideTask?.cancel()
                showDanmakuSettings = true
            }

            GlassIconButton(
                systemName: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: 38
            ) {
                toggleFullscreen()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    /// 人气 + 弹幕连接状态。人气优先用 WebSocket 推的实时值，
    /// 拿不到时退回列表接口带的人数，避免一开始就显示 0。
    private var liveBadge: some View {
        let count = danmaku.popularity > 0 ? danmaku.popularity : (room.online ?? 0)
        return HStack(spacing: 4) {
            Circle()
                .fill(danmaku.isConnected ? Color.red : Theme.inkFaint)
                .frame(width: 5, height: 5)
            Text(count.biliCount)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassSurface(.regular, in: .capsule)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
            Text(danmaku.isConnected
                 ? "\(danmaku.statusText) · 转动手机进入全屏"
                 : (danmaku.statusText.isEmpty ? "弹幕未连接" : danmaku.statusText))
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(.regular, in: .capsule)
        .padding(.bottom, 18)
    }

    // MARK: - 浮层

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white).scaleEffect(1.15)
            Text("正在连接直播间…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
        }
        .padding(22)
        .glassSurface(.regular, in: .rect(cornerRadius: 20))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button("返回") { close() }
                .buttonStyle(.liquidGlass)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .glassSurface(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - 控制条显隐

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible { scheduleAutoHide() }
    }

    /// 在全屏里看直播时控制条一直挂着太碍事，静置几秒自动收起来。
    /// 竖屏有信息栏，下面还有内容要看，就不自动收。
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard isFullscreen else { return }
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    controlsVisible = false
                }
            }
        }
    }

    // MARK: - 全屏

    private func toggleFullscreen() {
        if isFullscreen {
            withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = false }
            OrientationLock.forcePortrait()
        } else {
            controlsVisible = true
            withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = true }
            OrientationLock.forceLandscape()
            scheduleAutoHide()
        }
    }

    /// 跟随手机物理方向同步全屏状态。
    ///
    /// 这里**不请求**任何转屏——mask 已经放开，系统会自己把界面转过去，
    /// 我们只负责切布局。再调 requestGeometryUpdate 反而会和用户的手势打架。
    private func syncWithDeviceOrientation() {
        let orientation = UIDevice.current.orientation
        guard orientation.isLandscape || orientation.isPortrait else { return }

        if orientation.isLandscape {
            guard !isFullscreen else { return }
            controlsVisible = true
            withAnimation(.easeInOut(duration: 0.22)) { isFullscreen = true }
            scheduleAutoHide()
        } else {
            guard isFullscreen else { return }
            autoHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.22)) {
                isFullscreen = false
                controlsVisible = true
            }
        }
    }

    // MARK: - 数据

    private func start() async {
        async let stream: Void = loadStream()
        async let bullets: Void = danmaku.connect(roomID: room.id)
        _ = await (stream, bullets)
    }

    private func loadStream() async {
        do {
            let data = try await BiliAPI.shared.livePlayURL(roomID: room.id)
            guard let urlString = data.durl?.first?.url, let url = URL(string: urlString) else {
                errorMessage = "该直播间未返回可播放地址"
                isLoading = false
                return
            }
            // 直播 m3u8 有防盗链，必须经 LiveStreamLoader 注入 Referer
            let asset = LiveStreamLoader.makeAsset(url)
            let item = AVPlayerItem(asset: asset)
            let created = AVPlayer(playerItem: item)
            created.automaticallyWaitsToMinimizeStalling = true
            created.play()
            player = created

            // 等第一帧就绪再撤掉「正在连接」，否则会先黑一下
            await waitUntilReady(item)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// 轮询播放项状态。不用 KVO/Combine 是因为这里只需一个很短的前置等待，
    /// 而且要在页面消失时能被打断。
    private func waitUntilReady(_ item: AVPlayerItem) async {
        for _ in 0..<60 {
            if Task.isCancelled { return }
            switch item.status {
            case .readyToPlay:
                isLoading = false
                return
            case .failed:
                errorMessage = item.error?.localizedDescription ?? "直播流加载失败"
                isLoading = false
                return
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // 超时就不卡在 loading 上，让它继续在后台缓冲
        isLoading = false
    }

    private func close() {
        player?.pause()
        danmaku.disconnect()
        dismiss()
    }
}
