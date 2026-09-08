import SwiftUI
import SwiftData

/// 「我的」：日历导出、数据说明、缓存管理。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LiveCatalogSync.self) private var sync
    @Environment(RemoteConfig.self) private var config
    @Query(sort: \ScheduleItem.startAt) private var items: [ScheduleItem]
    @Binding var toast: ToastMessage?

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var confirmClear = false
    @State private var showIPManager = false

    private var unexported: [ScheduleItem] { items.filter { $0.ekEventIdentifier == nil && $0.startAt >= Date() } }

    var body: some View {
        NavigationStack {
            List {
                Section("Apple 日历") {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Label("导出到 Apple 日历", systemImage: "calendar.badge.plus")
                            Spacer()
                            if isExporting { ProgressView() } else { Text("\(unexported.count) 条待导出").foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(unexported.isEmpty || isExporting)
                    Text("导出是单向的一次性动作：之后在本 App 修改不会同步，需要重新导出。")
                        .font(Theme.F.caption).foregroundStyle(.secondary)
                }

                if config.pilgrimageLayerEnabled {
                    Section("巡礼") {
                        Button { showIPManager = true } label: { Label("订阅作品", systemImage: "sparkles.rectangle.stack") }
                    }
                }

                Section("数据") {
                    LabeledContent("上次同步", value: sync.lastSyncedAt.map { Fmt.fullDay.string(from: $0) + " " + Fmt.time.string(from: $0) } ?? "尚未同步")
                    Button("立即同步") { Task { await sync.sync(context: context, force: true) } }
                    Button("清除演出缓存", role: .destructive) { confirmClear = true }
                }

                Section("数据说明") {
                    Text("日程只保存在这台设备上，没有账号系统，换设备不会迁移。")
                    Text(config.disclaimers["hotel"] ?? "本 App 不提供酒店预订，房价与空房请以官网为准。")
                    Text(config.disclaimers["pilgrimage"] ?? "巡礼地点数据提供：Anitabi (CC BY-NC-SA 4.0)")
                    Text(config.disclaimers["walletPass"] ?? "Wallet 卡片是行程提醒，不是入场券。")
                }
                .font(Theme.F.caption)

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("服务器", value: LiveTimerAPI.production.baseURL.host() ?? "-")
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showIPManager) { IPSubscriptionView() }
            .alert("日历导出", isPresented: .init(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(exportError ?? "") }
            .confirmationDialog("清除缓存的演出与场馆数据？日程不受影响。", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除并重新拉取", role: .destructive) {
                    sync.resetCache(context: context)
                    Task { await sync.sync(context: context, force: true) }
                }
            }
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let count = try await CalendarExporter.export(unexported)
            try? context.save()
            toast = ToastMessage(text: "已添加到日历 \(count) 条", detail: "之后在本 App 修改不会同步")
        } catch {
            exportError = error.localizedDescription
        }
    }
}
