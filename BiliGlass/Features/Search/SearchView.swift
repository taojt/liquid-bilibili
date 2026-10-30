import SwiftUI
import OSLog

/// 搜索页：空态给热搜榜，输入后出双列视频结果。
///
/// 首页顶部那条只是「看起来像输入框」的入口（点了进这里），
/// 真正的 TextField 在本页，这样首页不用一直挂一个焦点控件。
struct SearchView: View {
    private static let logger = Logger(subsystem: "com.biliglass.app", category: "search")

    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var results: [VideoCellModel] = []
    @State private var hotWords: [SearchHotWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var page = 1
    @State private var hasMore = false
    @FocusState private var focused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            CanvasBackdrop()

            VStack(spacing: 0) {
                searchBar
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .hidesFloatingTabBar()
        .task {
            focused = true
            await loadHotWords()
            if let preset = DebugEntry.keyword {
                keyword = preset
                await search(reset: true)
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)

                TextField("搜索视频、UP 主", text: $keyword)
                    .focused($focused)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.pink)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        Task { await search(reset: true) }
                    }

                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        results = []
                        hasSearched = false
                        errorMessage = nil
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.liquidPress)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Button("取消") { dismiss() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.pink)
                .buttonStyle(.liquidPress)
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if hasSearched {
                resultSection
            } else {
                hotSection
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var resultSection: some View {
        if isLoading, results.isEmpty {
            ProgressView()
                .tint(Theme.pink)
                .padding(.vertical, 100)
        } else if let errorMessage, results.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.inkFaint)
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkDim)
                    .multilineTextAlignment(.center)
                Button("重试") { Task { await search(reset: true) } }
                    .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 90)
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.inkFaint)
                Text("没有找到「\(keyword)」相关的视频")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
        } else {
            VStack(spacing: 14) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { model in
                        NavigationLink {
                            VideoDetailView(bvid: model.id, fallbackTitle: model.title)
                        } label: {
                            VideoGridCard(model: model)
                        }
                        .buttonStyle(.cardPress)
                        .task {
                            if model.id == results.last?.id, hasMore, !isLoading {
                                await search(reset: false)
                            }
                        }
                    }
                }

                if isLoading {
                    ProgressView().tint(Theme.pink).padding(.top, 8)
                } else if !hasMore {
                    Text("没有更多了")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 60)
        }
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.pink)
                    .frame(width: 3, height: 13)
                    .clipShape(.capsule)
                Text("bilibili 热搜")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            if hotWords.isEmpty {
                ProgressView().tint(Theme.pink).padding(.vertical, 40)
            } else {
                // 这里刻意不用 glassEffect：大面积的玻璃会形成一圈很突兀的镜面高光，
                // 长列表属于「内容载体」，用半透明实心 + 细描边更稳也更清晰。
                VStack(spacing: 0) {
                    ForEach(Array(hotWords.enumerated()), id: \.element.id) { index, word in
                        Button {
                            keyword = word.display
                            Task { await search(reset: true) }
                        } label: {
                            hotRow(index: index, word: word)
                        }
                        .buttonStyle(.liquidPress)

                        if index < hotWords.count - 1 {
                            Rectangle()
                                .fill(Theme.ink.opacity(0.07))
                                .frame(height: 0.5)
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(Theme.ink.opacity(0.055), in: .rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.ink.opacity(0.09), lineWidth: 0.5)
                }
            }
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, 4)
        .padding(.bottom, 60)
    }

    private func hotRow(index: Int, word: SearchHotWord) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(index < 3 ? Theme.pink : Theme.inkFaint)
                .frame(width: 20)

            Text(word.display)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let heat = word.heatScore, heat > 0 {
                Text(heat.biliCount)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    // MARK: - 数据

    private func loadHotWords() async {
        guard hotWords.isEmpty else { return }
        if let data = try? await BiliAPI.shared.searchHotWords() {
            hotWords = data.trending?.list ?? []
        }
    }

    private func search(reset: Bool) async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if reset {
            page = 1
            results = []
            hasMore = true
            errorMessage = nil
            hasSearched = true
            focused = false
        }
        guard !isLoading, hasMore else { return }

        isLoading = true
        do {
            let data = try await BiliAPI.shared.searchVideos(keyword: query, page: page)
            let fresh = (data.result ?? []).compactMap { $0.cellModel }
            Self.logger.notice(
                "search ok keyword=\(query, privacy: .public) raw=\(data.result?.count ?? -1) usable=\(fresh.count) page=\(self.page)"
            )
            let existing = Set(results.map(\.id))
            results.append(contentsOf: fresh.filter { !existing.contains($0.id) })
            hasMore = !fresh.isEmpty
            page += 1
        } catch {
            Self.logger.error("search failed keyword=\(query, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }
}
