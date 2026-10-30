import SwiftUI

/// 收藏页：先列出收藏夹，再进具体收藏夹看视频。
///
/// 收藏夹 id 必须带 `up_mid` 才能列出，所以要先拿到当前账号 UID。
struct FavoritesView: View {
    @State private var folders: [FavFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var showLogin = false

    private var auth: AuthService { AuthService.shared }

    var body: some View {
        ZStack {
            CanvasBackdrop()

            ScrollView {
                VStack(spacing: 12) {
                    if !auth.isLoggedIn {
                        loginGate
                    } else if folders.isEmpty {
                        if isLoading {
                            ProgressView().tint(Theme.pink).padding(.vertical, 80)
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else {
                            Text("还没有收藏夹")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkFaint)
                                .padding(.vertical, 80)
                        }
                    } else {
                        ForEach(folders) { folder in
                            NavigationLink {
                                FavFolderContentView(mediaID: folder.id, title: folder.title)
                            } label: {
                                folderRow(folder)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 6)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .onChange(of: showLogin) { _, presented in
            guard !presented else { return }
            Task {
                await auth.refreshProfile()
                await load()
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    // MARK: - 行

    private func folderRow(_ folder: FavFolder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.pink)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.tint(Theme.pink.opacity(0.3)), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(folder.mediaCount ?? 0) 个视频")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - 状态

    private var loginGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.pink.opacity(0.85))
            Text("登录后可查看收藏夹")
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

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await load() } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - 数据

    private func load() async {
        guard auth.isLoggedIn else { return }
        guard let mid = auth.userID else {
            errorMessage = "无法获取用户 ID，请重新登录"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let data = try await BiliAPI.shared.favFolders(mid: mid)
            folders = data.list ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 单个收藏夹内的视频列表
struct FavFolderContentView: View {
    let mediaID: Int
    let title: String

    @State private var store: VideoFeedStore

    init(mediaID: Int, title: String) {
        self.mediaID = mediaID
        self.title = title
        _store = State(initialValue: VideoFeedStore(source: .favorites(mediaID: mediaID)))
    }

    var body: some View {
        ZStack {
            CanvasBackdrop()
            VideoFeedGrid(store: store, emptyHint: "这个收藏夹是空的", bottomInset: 40)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
    }
}
