import SwiftUI
import AVFoundation
import UIKit

/// 视频详情页 = 播放器 + 信息区 + 相关推荐。
///
/// 播放器层始终只有一个 `AVPlayer` 实例，全屏只是把同一个 PlayerLayerView
/// 换到覆盖全屏的容器里，因此切换过程不会重新起播、不会丢进度。
struct VideoDetailView: View {
    let bvid: String
    var fallbackTitle: String = ""
    /// 外部传入的续播起点（历史记录里的 progress）。为空时退回本地记录的断点。
    var resumeAt: Int? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var engine = PlaybackEngine()
    @State private var interaction = InteractionService()
    @State private var comment = CommentService()
    @State private var detail: VideoDetail?
    @State private var related: [VideoCellModel] = []
    @State private var loadError: String?
    @State private var resumeHint: String?

    /// 三连动效的播放计数，每 +1 播一次
    @State private var tripleTick = 0
    /// 上一次长按的时间点。长按松手也会触发 Button 的 action，
    /// 用时间窗把紧跟其后的那次「短按」吞掉，避免三连又顺手取消点赞。
    @State private var lastLongPressAt = Date.distantPast

    @State private var danmaku: [DanmakuItem] = []
    @State private var showDanmaku = true
    @State private var showDanmakuSettings = false

    /// 弹幕外观偏好（不透明度 / 显示区域）全局共用一份
    private var danmakuSettings: DanmakuSettings { DanmakuSettings.shared }

    /// 画中画（小窗播放）管理，全局单例
    private var pip: PiPManager { PiPManager.shared }

    @State private var isFullscreen = false
    /// 上一次同步到布局的物理方向。方向同步只认「变化」，防止
    /// 转屏过程中补发的同方向通知把全屏状态打回去
    @State private var lastSyncedOrientation: UIDeviceOrientation = .unknown
    @State private var controlsVisible = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var descExpanded = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if isFullscreen {
                fullscreenLayer
                    .zIndex(2)
            } else {
                page
                    .overlay(alignment: .bottom) { toastView }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // 登记进悬浮底栏闸门：详情页（含全屏播放期间）整段生命周期内底栏收起
        .hidesFloatingTabBar()
        .statusBarHidden(isFullscreen)
        .task { await load() }
        .onChange(of: engine.isReady) { _, ready in
            guard ready else { return }
            // 调试：模拟器没法按 Home 键也没法点按钮，自动走一次对应动作截图验证
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if DebugEntry.pip {
                    pip.startIfPossible()
                } else if DebugEntry.fullscreen {
                    enterFullscreen()
                }
            }
        }
        .onAppear {
            // 播放页驻留期间放开旋转，手机转横屏就进全屏
            OrientationLock.allowRotation()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            OrientationLock.lockPortrait()
            isFullscreen = false
            // 先收小窗再停引擎：反过来小窗里会定格一帧黑屏画面
            pip.stopIfNeeded()
            engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncWithDeviceOrientation()
        }
        .sheet(isPresented: $showDanmakuSettings) {
            DanmakuSettingsSheet()
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 竖屏页面

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    playerBox

                    VStack(alignment: .leading, spacing: 18) {
                        titleBlock
                        statRow
                        actionBar
                        upBlock
                        descBlock
                        commentBlock.id("comment-section")
                        relatedBlock
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.top, 16)
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            // 详情拿到后评论区才开始渲染，所以不能按固定延时滚——
            // 滚早了目标 id 还不存在，scrollTo 会被静默忽略
            .onChange(of: detail?.aid) { _, newValue in
                guard DebugEntry.comment, newValue != nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("comment-section", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - 播放器（竖屏内嵌）

    private var playerBox: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let player = engine.player {
                    PlayerLayerView(player: player)
                } else {
                    coverPlaceholder
                }
            }
            .overlay {
                // 小窗激活时盖住本地画面：系统小窗在渲染视频，
                // 本地 layer 这时候是黑的，铺一层说明避免像坏掉一样
                if pip.isActive {
                    pipPlaceholder
                }
            }
            .overlay { danmakuLayer }
            .overlay { statusOverlay }
            .overlay(alignment: .center) { centerPlayButton }
            .overlay(alignment: .bottom) { inlineBottomBar }
            .overlay(alignment: .topLeading) { backButton }
            .overlay(alignment: .topTrailing) { inlineControlCluster }
            .overlay(alignment: .topLeading) { diagHud }
            .clipped()
    }

    /// 只能在真机上靠截图排查时开（`debugDiag`）：把画中画三态和全屏态打在画面上
    @ViewBuilder
    private var diagHud: some View {
        if DebugEntry.diag {
            VStack(alignment: .leading, spacing: 4) {
                Text(pip.debugText)
                Text("fs=\(isFullscreen) ready=\(engine.isReady) play=\(engine.isPlaying)")
                Text("dev=\(String(describing: UIDevice.current.orientation.rawValue))")
            }
            .font(.system(size: 20, weight: .bold, design: .monospaced))
            .foregroundStyle(.green)
            .padding(10)
            .background(.black.opacity(0.85), in: .rect(cornerRadius: 8))
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 120)
        }
    }

    /// 小窗播放中的占位：保持层叠结构（内容源 layer 必须活着），只挡视觉
    private var pipPlaceholder: some View {
        ZStack {
            Color.black
            VStack(spacing: 10) {
                Image(systemName: "pip.exit")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.pink)
                Text("小窗播放中")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("回到本页或从小窗点还原按钮继续看")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .transition(.opacity)
    }

    // MARK: - 弹幕层

    @ViewBuilder
    private var danmakuLayer: some View {
        if showDanmaku, !danmaku.isEmpty, engine.isReady {
            DanmakuOverlay(
                items: danmaku,
                mediaTime: engine.currentTime,
                rate: engine.playbackRate,
                isPlaying: engine.isPlaying,
                fontSize: 13,
                // 竖屏内嵌播放器右上角有一排 34pt 的圆形按钮（含 10pt 外距），
                // 弹幕从 58 起排，正好落在按钮下方，不会压住控件
                topInset: 58,
                opacity: danmakuSettings.opacity,
                area: danmakuSettings.area
            )
            .transition(.opacity)
        }
    }

    /// 全屏时把弹幕限制在 16:9 的画面区域内，避免飘到左右黑边上
    private var fullscreenDanmakuLayer: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if showDanmaku, !danmaku.isEmpty, engine.isReady {
                    DanmakuOverlay(
                        items: danmaku,
                        mediaTime: engine.currentTime,
                        rate: engine.playbackRate,
                        isPlaying: engine.isPlaying,
                        fontSize: 16,
                        opacity: danmakuSettings.opacity,
                        area: danmakuSettings.area
                    )
                }
            }
    }

    private var coverPlaceholder: some View {
        AsyncImage(url: (detail?.pic ?? "").biliThumbnail(width: 720)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.35))
            } else {
                Rectangle().fill(Theme.glow(for: bvid))
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if engine.isLoading {
            VStack(spacing: 10) {
                ProgressView().tint(.white).scaleEffect(1.1)
                Text("正在解析播放流…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else if let message = engine.errorMessage ?? loadError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("重试") {
                    loadError = nil
                    Task { await reloadPlayback() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(16)
            .frame(maxWidth: 260)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var centerPlayButton: some View {
        if engine.isReady, !engine.isLoading {
            Button {
                engine.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.pink.opacity(0.6)).interactive(), in: .circle)
        }
    }

    private var backButton: some View {
        GlassIconButton(systemName: "chevron.left", size: 34) {
            engine.stop()
            dismiss()
        }
        .padding(10)
    }

    private var fullscreenButton: some View {
        GlassIconButton(systemName: "arrow.up.left.and.arrow.down.right", size: 34) {
            enterFullscreen()
        }
        .opacity(engine.isReady ? 1 : 0.4)
        .disabled(!engine.isReady)
    }

    /// 竖屏下的控制簇：弹幕开关 / 弹幕设置 / 倍速 / 小窗 / 全屏
    private var inlineControlCluster: some View {
        HStack(spacing: 6) {
            danmakuToggle
            danmakuSettingsButton
            speedMenu
            pipButton
            fullscreenButton
        }
        .padding(10)
    }

    /// 小窗播放按钮。系统不支持（或播放层还没挂上）时隐藏而不是禁用，
    /// 保持控制簇紧凑。
    @ViewBuilder
    private var pipButton: some View {
        if pip.isAvailable, engine.isReady {
            GlassIconButton(systemName: "pip.enter", size: 34) {
                pip.toggle()
            }
        }
    }

    // MARK: - 弹幕 / 倍速控件

    private var danmakuSettingsButton: some View {
        Button {
            showDanmakuSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(danmakuSettings.isDefault ? Theme.ink : Theme.pink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassEffect(
            danmakuSettings.isDefault
                ? .regular.interactive()
                : .regular.tint(Theme.pink.opacity(0.4)).interactive(),
            in: .circle
        )
    }

    private var danmakuToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                showDanmaku.toggle()
            }
        } label: {
            Image(systemName: showDanmaku ? "text.bubble.fill" : "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showDanmaku ? Theme.ink : Theme.inkFaint)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassEffect(
            showDanmaku
                ? .regular.tint(Theme.pink.opacity(0.55)).interactive()
                : .regular.interactive(),
            in: .circle
        )
        .disabled(danmaku.isEmpty)
        .opacity(danmaku.isEmpty ? 0.4 : 1)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(engine.availableRates, id: \.self) { rate in
                Button {
                    engine.setRate(rate)
                } label: {
                    if rate == engine.playbackRate {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(engine.playbackRate == 1.0 ? "倍速" : rateLabel(engine.playbackRate))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .glassEffect(
                    engine.playbackRate == 1.0
                        ? .regular.interactive()
                        : .regular.tint(Theme.pink.opacity(0.55)).interactive(),
                    in: .capsule
                )
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "1.0x" : String(format: "%gx", rate)
    }

    @ViewBuilder
    private var inlineBottomBar: some View {
        if engine.isReady {
            HStack(spacing: 10) {
                Text(Int(engine.currentTime).clockText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.ink)

                progressSlider

                Text(Int(engine.duration).clockText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(10)
        }
    }

    private var progressSlider: some View {
        Slider(
            value: Binding(
                get: { scrubbing ? scrubValue : engine.currentTime },
                set: { scrubValue = $0 }
            ),
            in: 0...Swift.max(1, engine.duration),
            onEditingChanged: { editing in
                if editing {
                    scrubValue = engine.currentTime
                    scrubbing = true
                } else {
                    engine.seek(to: scrubValue)
                    scrubbing = false
                }
            }
        )
        .tint(Theme.pink)
        .controlSize(.mini)
    }

    // MARK: - 全屏层

    private var fullscreenLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = engine.player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            }

            // 小窗激活时盖住全屏画面（与竖屏内嵌同理）
            if pip.isActive {
                pipPlaceholder
                    .ignoresSafeArea()
            }

            fullscreenDanmakuLayer
                .allowsHitTesting(false)

            if controlsVisible {
                VStack {
                    fullscreenTopBar
                    Spacer()
                    fullscreenBottomBar
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .transition(.opacity)
            }

            if DebugEntry.diag {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pip.debugText)
                    Text("fs=\(isFullscreen) ready=\(engine.isReady) play=\(engine.isPlaying)")
                }
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .padding(10)
                .background(.black.opacity(0.85), in: .rect(cornerRadius: 8))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 60)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible.toggle()
            }
        }
    }

    private var fullscreenTopBar: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemName: "arrow.down.right.and.arrow.up.left", size: 38) {
                exitFullscreen()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.title ?? fallbackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let owner = detail?.owner.name {
                    Text(owner)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            danmakuToggle
            danmakuSettingsButton
            speedMenu
            pipButton
            qualityMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(engine.availableQN, id: \.self) { qn in
                Button {
                    Task { await engine.switchQuality(to: qn) }
                } label: {
                    if qn == engine.currentQN {
                        Label(BiliQuality.name(for: qn), systemImage: "checkmark")
                    } else {
                        Text(BiliQuality.name(for: qn))
                    }
                }
            }
        } label: {
            Text(BiliQuality.badge(for: engine.currentQN))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(Theme.pink).interactive(), in: .capsule)
        }
    }

    private var fullscreenBottomBar: some View {
        HStack(spacing: 14) {
            Button {
                engine.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.pink).interactive(), in: .circle)

            Text(Int(engine.currentTime).clockText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)

            progressSlider

            Text(Int(engine.duration).clockText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - 信息区

    private var titleBlock: some View {
        Text(detail?.title ?? fallbackTitle)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let stat = detail?.stat {
                    chip("play.fill", "\(stat.view?.biliCount ?? "0") 播放")
                    chip("text.bubble.fill", "\(stat.danmaku?.biliCount ?? "0") 弹幕")
                    chip("hand.thumbsup.fill", "\(stat.like?.biliCount ?? "0") 点赞")
                    chip("bitcoinsign.circle.fill", "\(stat.coin?.biliCount ?? "0") 投币")
                    chip("star.fill", "\(stat.favorite?.biliCount ?? "0") 收藏")
                    chip("arrowshape.turn.up.right.fill", "\(stat.share?.biliCount ?? "0") 分享")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.inkDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: - 互动操作栏（点赞 / 投币 / 收藏 / UP主页）

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionButton(
                icon: interaction.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                title: likeTitle,
                active: interaction.liked,
                longPress: {
                    lastLongPressAt = Date()
                    Task { await performTripleLink() }
                }
            ) {
                // 长按松手时 Button 的 action 也会走一次，这里按时间窗吞掉
                guard Date().timeIntervalSince(lastLongPressAt) > 0.5 else { return }
                guard let aid = detail?.aid else { return }
                Task { await interaction.toggleLike(aid: aid) }
            }

            actionButton(
                icon: interaction.coinCount > 0 ? "bitcoinsign.circle.fill" : "bitcoinsign.circle",
                title: coinTitle,
                active: interaction.coinCount > 0
            ) {
                guard let aid = detail?.aid else { return }
                Task { await interaction.addCoin(aid: aid) }
            }

            actionButton(
                icon: interaction.favoured ? "star.fill" : "star",
                title: interaction.favoured ? "已收藏" : "收藏",
                active: interaction.favoured
            ) {
                guard let aid = detail?.aid else { return }
                Task { await interaction.toggleFavourite(aid: aid) }
            }

            upLinkButton
        }
        // 动效原点对准第一个按钮（赞）的中心：宽度平均分四份，高度 54
        .overlay(alignment: .topLeading) {
            TripleLinkBurst(
                tick: tripleTick,
                frozenProgress: DebugEntry.tripleBurst ? 0.55 : nil
            )
        }
        .sensoryFeedback(.success, trigger: tripleTick)
    }

    /// 长按点赞：一键三连。只有确实做成了动作才播动效。
    private func performTripleLink() async {
        guard let aid = detail?.aid else { return }
        let outcome = await interaction.tripleAction(aid: aid)
        guard outcome.hasAction else { return }
        tripleTick += 1
    }

    @ViewBuilder
    private var commentBlock: some View {
        if let aid = detail?.aid {
            CommentSection(
                service: comment,
                aid: aid,
                upMid: detail?.owner.mid ?? 0
            )
        }
    }

    private var likeTitle: String {
        let base = detail?.stat?.like ?? 0
        return (base + interaction.likeDelta()).biliCount
    }

    private var coinTitle: String {
        let base = detail?.stat?.coin ?? 0
        return (base + interaction.coinCount).biliCount
    }

    private func actionButton(
        icon: String,
        title: String,
        active: Bool,
        longPress: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Theme.pink : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(
            active
                ? .regular.tint(Theme.pink.opacity(0.28)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 16)
        )
        // 用 simultaneousGesture 而不是 `.onLongPressGesture`：
        // 后者会把 Button 的点击吃掉，短按点赞就失效了
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in longPress?() }
        )
    }

    private var upLinkButton: some View {
        NavigationLink {
            if let owner = detail?.owner {
                UserSpaceView(mid: owner.mid, fallbackName: owner.name, fallbackFace: owner.face)
            } else {
                EmptyView()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text("UP主")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .disabled(detail == nil)
    }

    @ViewBuilder
    private var toastView: some View {
        if let message = interaction.toast ?? comment.toast ?? resumeHint {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var upBlock: some View {
        NavigationLink {
            if let owner = detail?.owner {
                UserSpaceView(mid: owner.mid, fallbackName: owner.name, fallbackFace: owner.face)
            } else {
                EmptyView()
            }
        } label: {
            GlassPanel(interactive: true, corner: 20) {
                HStack(spacing: 12) {
                    upAvatar

                    VStack(alignment: .leading, spacing: 3) {
                        Text(detail?.owner.name ?? "未知UP主")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text("UP主")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.pink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.pink.opacity(0.18), in: .capsule)
                            Text("UID \(detail?.owner.mid ?? 0)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .disabled(detail == nil)
    }

    private var upAvatar: some View {
        AsyncImage(url: (detail?.owner.face ?? "").biliImageURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.tint(Theme.purple), in: .circle)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(.circle)
    }

    @ViewBuilder
    private var descBlock: some View {
        if let desc = detail?.desc, !desc.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("简介")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink.opacity(0.86))
                    .lineSpacing(4)
                    .lineLimit(descExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.snappy(duration: 0.22)) { descExpanded.toggle() }
                } label: {
                    Text(descExpanded ? "收起" : "展开")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var relatedBlock: some View {
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Theme.pink)
                        .frame(width: 3, height: 13)
                        .clipShape(.capsule)
                    Text("相关推荐")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(related) { model in
                        NavigationLink {
                            VideoDetailView(bvid: model.id, fallbackTitle: model.title)
                        } label: {
                            VideoGridCard(model: model)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 全屏切换

    /// 手动点全屏按钮：切布局 + 请求横屏
    private func enterFullscreen() {
        // 把当前物理方向记成"已同步"，转屏过程中补发的同方向通知就不会
        // 把刚切进来的全屏又打回竖屏
        lastSyncedOrientation = UIDevice.current.orientation
        controlsVisible = true
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullscreen = true
        }
        OrientationLock.forceLandscape()
    }

    /// 手动点退出按钮：切布局 + 请求竖屏
    private func exitFullscreen() {
        lastSyncedOrientation = UIDevice.current.orientation
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullscreen = false
        }
        OrientationLock.forcePortrait()
    }

    /// 跟随手机物理方向同步全屏状态。
    ///
    /// 这里**不请求**任何转屏——mask 已经放开，系统会自己把界面转过去，
    /// 我们只负责把布局切成全屏/竖屏两种形态。如果这里再调
    /// requestGeometryUpdate，反而会和用户的手势打架。
    ///
    /// 关键细节：只响应**方向变化**，不按绝对方向处理。点全屏按钮时
    /// `requestGeometryUpdate` 会把界面转过去，期间系统会补发一条
    /// orientation 通知（此刻物理设备往往还没转过来，仍是 portrait），
    /// 如果按绝对值处理，这条通知会把刚进的全屏立刻打回竖屏——
    /// 表现为「全屏按钮点了没反应」。
    private func syncWithDeviceOrientation() {
        let orientation = UIDevice.current.orientation
        guard orientation.isLandscape || orientation.isPortrait else { return }
        guard orientation != lastSyncedOrientation else { return }
        lastSyncedOrientation = orientation

        if orientation.isLandscape {
            guard !isFullscreen else { return }
            controlsVisible = true
            withAnimation(.easeInOut(duration: 0.22)) {
                isFullscreen = true
            }
        } else {
            guard isFullscreen else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                isFullscreen = false
            }
        }
    }

    // MARK: - 数据

    private func load() async {
        guard detail == nil else { return }
        if let fetched = try? await BiliAPI.shared.videoDetail(bvid: bvid) {
            detail = fetched
            let startAt = resolveStart(detail: fetched)
            await engine.load(detail: fetched, startAt: Double(startAt))
            if let rate = DebugEntry.rate {
                engine.setRate(rate)
            }
            loadDanmaku(cid: fetched.cid)
            await interaction.load(aid: fetched.aid)
            // 评论独立拉取，不挡住起播和下面几个 await
            let aid = fetched.aid
            Task { await comment.load(aid: aid) }
            if startAt > 0 {
                showResumeHint(startAt)
            }
            if DebugEntry.danmakuSettings {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showDanmakuSettings = true
            }
            if DebugEntry.tripleBurst {
                // 只播动效，不真的调接口——未登录也能截图验证动画。
                // 连播几次，便于脚本抓帧。
                for _ in 0..<5 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    tripleTick += 1
                }
            }
        } else {
            loadError = "无法获取视频详情"
        }
        await loadRelated()
    }

    /// 续播起点：优先用历史记录给的 progress，其次用本地记录的断点。
    private func resolveStart(detail: VideoDetail) -> Int {
        if let resumeAt, resumeAt > 0 {
            return resumeAt
        }
        return PlaybackMemory.position(for: detail.bvid) ?? 0
    }

    private func showResumeHint(_ seconds: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            resumeHint = "已从 \(seconds.durationText) 继续播放"
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.2)) { resumeHint = nil }
        }
    }

    /// 弹幕独立于播放链路加载：拿不到就当作没有弹幕，不能影响视频起播
    private func loadDanmaku(cid: Int) {
        Task {
            danmaku = await DanmakuLoader.load(cid: cid)
        }
    }

    private func reloadPlayback() async {
        guard let detail else {
            await load()
            return
        }
        await engine.load(detail: detail, startAt: engine.currentTime)
    }

    private func loadRelated() async {
        guard related.isEmpty else { return }
        if let list = try? await BiliAPI.shared.relatedVideos(bvid: bvid) {
            related = list
                .filter { !$0.bvid.isEmpty && $0.bvid != bvid }
                .prefix(8)
                .map { VideoCellModel(video: $0) }
        }
    }
}
