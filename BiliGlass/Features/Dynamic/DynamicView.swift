import SwiftUI

/// 动态页：关注 UP 主的动态时间线。
///
/// 走 `polymer/web-dynamic/v1/feed/all`，混排投稿、图文与转发；
/// 每条头部的 UP 名可点进个人主页，投稿卡片可点进播放页。
struct DynamicView: View {
    @State private var store = DynamicStore()
    @State private var showLogin = false
    @State private var debugUser: MIDTarget?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $debugUser) { target in
            UserSpaceView(mid: target.id)
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .onChange(of: showLogin) { _, presented in
            // 登录成功后重新拉一次（此前被 -101 拒绝过）
            guard !presented else { return }
            Task {
                await AuthService.shared.refreshProfile()
                await store.refresh()
            }
        }
        .task {
            if let mid = DebugEntry.mid {
                debugUser = MIDTarget(id: mid)
            }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("动态")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("关注 UP 主的最新动态")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer(minLength: 0)

            GlassIconButton(systemName: "arrow.clockwise", size: 34) {
                Task { await store.refresh() }
            }
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            listBody
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 4)
                .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var listBody: some View {
        if store.needsLogin {
            loginGate
        } else if store.items.isEmpty {
            if store.isLoading {
                loadingState
            } else if let error = store.errorMessage {
                errorState(error)
            } else {
                emptyState
            }
        } else {
            timeline
        }
    }

    private var timeline: some View {
        LazyVStack(spacing: 12) {
            ForEach(store.items) { cell in
                DynamicCard(cell: cell)
                    .task { await store.loadMoreIfNeeded(current: cell) }
            }

            if store.isLoading {
                ProgressView()
                    .tint(Theme.pink)
                    .padding(.top, 14)
            } else if !store.hasMore, store.items.count > 4 {
                Text("没有更多动态了")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: - 各状态

    private var loginGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.pink.opacity(0.85))
            Text("登录后查看关注 UP 主的动态")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkDim)
            Button {
                showLogin = true
            } label: {
                Label("扫码登录", systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.pink)
            Text("正在加载动态…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 110)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.inkDim)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await store.refresh() }
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 34))
                .foregroundStyle(Theme.inkFaint)
            Text("关注 UP 主后，这里会显示他们的最新动态")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 110)
    }
}
