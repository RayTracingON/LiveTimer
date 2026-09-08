import SwiftUI
import SwiftData

/// IP 订阅页：后端策展的作品清单。这里叫「订阅作品」不叫「收藏」，没有心形图标。
struct IPSubscriptionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PilgrimageStore.self) private var store
    @Query(sort: \SubscribedIP.subscribedAt, order: .reverse) private var subscribed: [SubscribedIP]

    @State private var catalog: [LiveTimerAPI.IpCatalogEntry] = []
    @State private var searchResults: [LiveTimerAPI.IpCatalogEntry] = []
    @State private var loading = false
    @State private var searching = false
    @State private var error: String?
    @State private var query = ""
    @State private var prefecture: String?
    @State private var removing: SubscribedIP?
    @State private var searchTask: Task<Void, Never>?

    private var prefectures: [String] { Array(Set(catalog.compactMap(\.prefecture))).sorted() }

    private var filtered: [LiveTimerAPI.IpCatalogEntry] {
        catalog.filter { e in
            (prefecture == nil || e.prefecture == prefecture)
                && (query.isEmpty || [e.titleOriginal, e.titleCn, e.primaryCity].compactMap { $0 }.joined().localizedCaseInsensitiveContains(query))
        }
    }

    /// 搜索结果里去掉策展清单已有的，避免同一部作品出现两次。
    private var extraSearchResults: [LiveTimerAPI.IpCatalogEntry] {
        let known = Set(catalog.map(\.bangumiSubjectId))
        return searchResults.filter { !known.contains($0.bangumiSubjectId) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !subscribed.isEmpty {
                    Section("已订阅") {
                        ForEach(subscribed) { ip in
                            HStack(spacing: 12) {
                                cover(ip.coverUrl)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ip.titleCn ?? ip.titleOriginal).font(Theme.F.cardTitle)
                                    Text("\(ip.pointCount) 个地标" + (ip.pointsFetchedAt == nil ? " · 尚未拉取" : "")).font(Theme.F.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.progress?.subjectId == ip.bangumiSubjectId { ProgressView() }
                            }
                            .swipeActions { Button("移除", role: .destructive) { removing = ip } }
                        }
                    }
                }
                if !query.isEmpty {
                    Section(searching ? "搜索中…" : "搜索结果（\(extraSearchResults.count)）") {
                        if searching && extraSearchResults.isEmpty {
                            ProgressView()
                        } else if extraSearchResults.isEmpty {
                            Text("没有搜到有巡礼数据的作品。换个写法试试，日文原名通常更准。")
                                .font(Theme.F.caption).foregroundStyle(.secondary)
                        }
                        ForEach(extraSearchResults, id: \.bangumiSubjectId) { entry in
                            row(for: entry)
                        }
                    }
                }

                Section(catalog.isEmpty ? "作品清单" : (query.isEmpty ? "推荐作品（\(filtered.count)）" : "推荐作品中的匹配（\(filtered.count)）")) {
                    if loading && catalog.isEmpty {
                        ProgressView()
                    } else if let error {
                        Text(error).font(Theme.F.caption).foregroundStyle(Theme.C.warning)
                    } else if catalog.isEmpty {
                        Text("清单还是空的，运营录入后会显示在这里。").font(Theme.F.caption).foregroundStyle(.secondary)
                    }
                    ForEach(filtered, id: \.bangumiSubjectId) { entry in
                        row(for: entry)
                    }
                }
                if let p = store.progress {
                    Section { Label(p.stage, systemImage: "arrow.down.circle").font(Theme.F.caption) }
                }
                if let summary = store.lastFilterSummary {
                    Section { Label(summary, systemImage: "scope").font(Theme.F.caption) }
                }
                if let err = store.lastError {
                    Section { Text(err).font(Theme.F.caption).foregroundStyle(Theme.C.warning) }
                }
                Section {
                    Text("只保留距离你日程中演出场馆 100km 以内的地标。日程为空时会保留全部。")
                        .font(Theme.F.tag).foregroundStyle(.tertiary)
                    Text("巡礼地点数据提供：Anitabi（CC BY-NC-SA 4.0）。地标只在本机缓存，不会上传。")
                        .font(Theme.F.tag).foregroundStyle(.tertiary)
                }
            }
            .searchable(text: $query, prompt: "搜索任意作品（日文原名更准）")
            .onChange(of: query) { _, keyword in scheduleSearch(keyword) }
            .navigationTitle("订阅作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("全部") { prefecture = nil }
                        ForEach(prefectures, id: \.self) { p in Button(p) { prefecture = p } }
                    } label: { Label(prefecture ?? "都道府県", systemImage: "line.3.horizontal.decrease.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task { await loadCatalog() }
            .refreshable { await loadCatalog(); await store.refreshIfStale(context: context, force: true) }
            .confirmationDialog("移除「\(removing?.titleCn ?? removing?.titleOriginal ?? "")」？", isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("移除，保留已加入日程的地标") { if let ip = removing { store.unsubscribe(ip, deleteScheduleItems: false, context: context) } }
                Button("移除，并删除相关日程", role: .destructive) { if let ip = removing { store.unsubscribe(ip, deleteScheduleItems: true, context: context) } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    /// 清单和搜索结果共用一行的渲染。
    @ViewBuilder
    private func row(for entry: LiveTimerAPI.IpCatalogEntry) -> some View {
        let isSubscribed = subscribed.contains { $0.bangumiSubjectId == entry.bangumiSubjectId }
        HStack(spacing: 12) {
            cover(entry.coverUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.titleOriginal ?? "#\(entry.bangumiSubjectId)").font(Theme.F.cardTitle).lineLimit(1)
                if let cn = entry.titleCn { Text(cn).font(Theme.F.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text([entry.primaryCity, entry.pointCount.map { "\($0) 个地标" }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.F.tag).foregroundStyle(.tertiary)
            }
            Spacer()
            if store.progress?.subjectId == entry.bangumiSubjectId {
                ProgressView()
            } else {
                Button(isSubscribed ? "已添加" : "添加") {
                    Task { await store.subscribe(entry, context: context) }
                }
                .buttonStyle(.bordered)
                .tint(isSubscribed ? Theme.C.textTertiary : Theme.C.kind(.pilgrimage))
                .disabled(isSubscribed || store.progress != nil)
            }
        }
    }

    /// 输入停顿 400ms 再搜。每次搜索后端都要逐个校验 anitabi，别按键就打一次。
    private func scheduleSearch(_ keyword: String) {
        searchTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { searchResults = []; searching = false; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            searchResults = (try? await LiveTimerAPI.production.searchIpCatalog(trimmed)) ?? []
        }
    }

    private func cover(_ url: String?) -> some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { Theme.C.surfaceRaised }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func loadCatalog() async {
        loading = true
        defer { loading = false }
        do {
            catalog = try await LiveTimerAPI.production.ipCatalog().filter { $0.deleted != true && $0.isActive != false }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
