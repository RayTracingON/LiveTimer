import SwiftUI
import SwiftData
import MapKit

/// 点击色块弹出的详情。Live 类型可以进一步跳到完整的演出详情。
struct ScheduleItemDetailSheet: View {
    let item: ScheduleItem
    @Binding var toast: ToastMessage?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var live: CachedLive?
    @State private var showLiveDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        TagLabel(text: item.kind.label, color: Theme.C.kind(item.kind), filled: true)
                        if item.isSourceInvalid { TagLabel(text: "演出信息已失效", color: Theme.C.warning) }
                    }
                    Text(item.title).font(Theme.F.screenTitle).foregroundStyle(Theme.C.textPrimary)
                    if let sub = item.subtitle { Text(sub).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary) }

                    infoRow(icon: "clock", text: timeText)
                    if let note = item.note { infoRow(icon: "text.alignleft", text: note) }
                    if let loc = item.locationName {
                        infoRow(icon: "mappin.and.ellipse", text: [loc, item.locationAddress].compactMap { $0 }.joined(separator: "\n"))
                    }

                    if item.latitude != nil {
                        Button { openInMaps() } label: {
                            Label("导航到这里", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(Theme.F.body).foregroundStyle(Theme.C.textPrimary)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.C.surfaceRaised))
                        }
                        .buttonStyle(.plain)
                    }

                    if let live {
                        Button { showLiveDetail = true } label: {
                            Label("查看演出详情", systemImage: "music.mic")
                                .font(Theme.F.cardTitle).foregroundStyle(Theme.C.background)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.C.accentAlt))
                        }
                        .buttonStyle(.plain)
                        .navigationDestination(isPresented: $showLiveDetail) {
                            LiveDetailView(live: live, toast: $toast)
                        }
                    }

                    Button(role: .destructive) {
                        ScheduleStore.remove(item, in: context)
                        toast = ToastMessage(text: "已从日程移除", icon: "minus.circle.fill", tint: Theme.C.textSecondary)
                        dismiss()
                    } label: {
                        Label("从日程移除", systemImage: "trash")
                            .font(Theme.F.body).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .tint(Theme.C.accent)
                }
                .padding(Theme.M.screenPadding)
            }
            .background(Theme.C.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.tint(Theme.C.accent) }
            }
            .task { loadLive() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var timeText: String {
        if item.isAllDayBand {
            return "\(Fmt.fullDay.string(from: item.startAt)) 〜 \(Fmt.fullDay.string(from: item.effectiveEndAt))"
        }
        return "\(Fmt.fullDay.string(from: item.startAt)) \(Fmt.time.string(from: item.startAt))"
            + (item.endAt.map { " 〜 \(Fmt.time.string(from: $0))" } ?? "")
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.C.textTertiary).frame(width: 18)
            Text(text).font(Theme.F.body).foregroundStyle(Theme.C.textPrimary)
        }
    }

    private func loadLive() {
        guard item.kind == .live, let ref = item.sourceRef else { return }
        live = (try? context.fetch(FetchDescriptor<CachedLive>(predicate: #Predicate { $0.id == ref })))?.first
    }

    private func openInMaps() {
        guard let lat = item.latitude, let lng = item.longitude else { return }
        GoogleNavigation.open(latitude: lat, longitude: lng, name: item.locationName)
    }
}

/// 长按空白新建自定义安排。
struct NewCustomEventSheet: View {
    let startAt: Date
    @Binding var toast: ToastMessage?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var location = ""
    @State private var note = ""

    init(startAt: Date, toast: Binding<ToastMessage?>) {
        self.startAt = startAt
        self._toast = toast
        _start = State(initialValue: startAt)
        _end = State(initialValue: startAt.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                DatePicker("开始", selection: $start)
                DatePicker("结束", selection: $end, in: start...)
                TextField("地点（可选）", text: $location)
                TextField("备注（可选）", text: $note, axis: .vertical)
            }
            .navigationTitle("新建安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ScheduleStore.addCustom(title: title.trimmingCharacters(in: .whitespaces), startAt: start, endAt: end,
                                                note: note.isEmpty ? nil : note,
                                                locationName: location.isEmpty ? nil : location, in: context)
                        toast = ToastMessage(text: "已加入日程", detail: Fmt.fullDay.string(from: start))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
