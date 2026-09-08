import SwiftUI
import SwiftData
import MapKit

/// 巡礼地标详情：大图 h360、原名 + 译名、所属作品、集数时间点、署名区块（固定在截图正下方）。
struct PilgrimagePointDetailView: View {
    let point: CachedPilgrimagePoint
    let work: SubscribedIP?
    @Binding var toast: ToastMessage?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showSchedule = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AsyncImage(url: point.largeImageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { Theme.C.surfaceRaised.frame(height: 200) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.M.cardRadius))

                // 署名区块紧贴截图正下方，字号不小于 caption。
                AttributionRow(point: point)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.surface))

                Text(point.nameCn ?? point.name).font(Theme.F.screenTitle).foregroundStyle(Theme.C.textPrimary)
                if point.nameCn != nil { Text(point.name).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary) }
                if let work {
                    Label(work.titleCn ?? work.titleOriginal, systemImage: "sparkles").font(Theme.F.body).foregroundStyle(Theme.C.kind(.pilgrimage))
                }
                if let ep = point.episodeText { Label(ep, systemImage: "film").font(Theme.F.body).foregroundStyle(Theme.C.textSecondary) }

                GoogleMiniMap(latitude: point.latitude, longitude: point.longitude, title: point.nameCn ?? point.name,
                              color: Theme.C.kind(.pilgrimage))
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Theme.M.cardRadius))
                .allowsHitTesting(false)

                HStack(spacing: 10) {
                    Button { showSchedule = true } label: {
                        Label("加入日程", systemImage: "calendar.badge.plus")
                            .font(Theme.F.cardTitle).foregroundStyle(Theme.C.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.C.kind(.pilgrimage)))
                    }
                    .buttonStyle(.plain)
                    Button { navigate() } label: {
                        Label("导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.C.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.M.screenPadding)
        }
        .background(Theme.C.background)
        .navigationTitle("巡礼地标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.tint(Theme.C.accent) } }
        .sheet(isPresented: $showSchedule) { PilgrimageTimeSheet(point: point, work: work, toast: $toast) }
    }

    private func navigate() {
        GoogleNavigation.open(latitude: point.latitude, longitude: point.longitude, name: point.name)
    }
}

struct PilgrimageTimeSheet: View {
    let point: CachedPilgrimagePoint
    let work: SubscribedIP?
    @Binding var toast: ToastMessage?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var at = Calendar.jst.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("到访时间", selection: $at)
                Text("默认预留 1 小时。").font(Theme.F.caption).foregroundStyle(.secondary)
            }
            .navigationTitle(point.nameCn ?? point.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ScheduleStore.addPilgrimage(point: point, workTitle: work?.titleCn ?? work?.titleOriginal ?? "巡礼", at: at, in: context)
                        toast = ToastMessage(text: "已加入日程", detail: Fmt.fullDay.string(from: at), tint: Theme.C.kind(.pilgrimage))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
