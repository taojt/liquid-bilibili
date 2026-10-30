import SwiftUI

struct ProfileView: View {
    private var auth: AuthService { AuthService.shared }
    @State private var showLogin = false

    var body: some View {
        ZStack {
            CanvasBackdrop()

            Circle()
                .fill(Theme.blue.opacity(0.3))
                .frame(width: 380, height: 380)
                .blur(radius: 70)
                .offset(x: 100, y: -220)

            ScrollView {
                VStack(spacing: 18) {
                    Color.clear.frame(height: 12)
                    profileCard
                    appearanceCard
                    if auth.isLoggedIn {
                        contentCard
                        sessionCard
                        logoutButton
                    } else {
                        loginPrompt
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .task {
            if auth.profile == nil, auth.isLoggedIn {
                await auth.refreshProfile()
            }
        }
    }

    // MARK: - 用户卡

    private var profileCard: some View {
        GlassPanel(tint: nil, interactive: false, corner: 18) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 5) {
                    Text(auth.profile?.uname ?? "未登录")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(auth.isLoggedIn ? "UID \(auth.profile?.mid.map(String.init) ?? "-")" : "登录后可同步历史与收藏")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkDim)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private var avatar: some View {
        Group {
            if let face = auth.profile?.face, let url = face.biliImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.circle)
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.tint(Theme.purple), in: .circle)
    }

    // MARK: - 外观

    private var appearanceCard: some View {
        GlassPanel(corner: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.pink)
                    Text("外观")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Text(AppSettings.shared.appearance.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }

                HStack(spacing: 8) {
                    ForEach(AppSettings.Appearance.allCases) { mode in
                        appearanceChip(mode)
                    }
                }
            }
            .padding(16)
        }
    }

    private func appearanceChip(_ mode: AppSettings.Appearance) -> some View {
        let selected = AppSettings.shared.appearance == mode
        return Button {
            guard !selected else { return }
            withAnimation(.snappy(duration: 0.24)) {
                AppSettings.shared.appearance = mode
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.pink : Theme.inkDim)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(selected ? Theme.pink.opacity(0.16) : Theme.ink.opacity(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        selected ? Theme.pink.opacity(0.55) : Theme.ink.opacity(0.10),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 会话信息

    private var contentCard: some View {
        GlassPanel(tint: nil, interactive: false, corner: 16) {
            VStack(spacing: 0) {
                NavigationLink {
                    FavoritesView()
                } label: {
                    linkRow(icon: "star.fill", title: "我的收藏")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    private func linkRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.pink)
                .frame(width: 26, height: 26)
                .glassEffect(.regular.tint(Theme.pink.opacity(0.28)), in: .circle)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var sessionCard: some View {
        GlassPanel(tint: nil, interactive: false, corner: 16) {
            VStack(spacing: 0) {
                infoRow(label: "登录方式", value: "扫码登录")
                divider
                infoRow(label: "凭证存储", value: "钥匙串 Keychain")
                divider
                infoRow(label: "CSRF 令牌", value: auth.isLoggedIn ? "已就绪" : "缺失")
            }
            .padding(.vertical, 4)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 18)
    }

    // MARK: - 操作

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Text("还没有登录")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkDim)
            Button {
                showLogin = true
            } label: {
                Label("扫码登录", systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.top, 10)
    }

    private var logoutButton: some View {
        Button {
            auth.logout()
        } label: {
            Text("退出登录")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.glass)
    }
}
