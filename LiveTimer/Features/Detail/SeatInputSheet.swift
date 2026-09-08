import SwiftUI

/// 填座位。日本的演出入场方式分两种，字段完全不同，所以先选方式再填。
///
/// 指定席：ブロック（1階 / アリーナA 之类）+ 列 + 番号。
/// 站席：只有整理番号（入场顺序号），有些场次会再分ブロック。
struct SeatInputSheet: View {
    @Binding var seat: PassSeatInput
    var isSaving: Bool
    let onSave: (PassSeatInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @FocusState private var focused: Field?

    private enum Mode: String, CaseIterable {
        case reserved = "指定席"
        case standing = "站席 · 整理番号"
    }

    private enum Field: Hashable { case section, row, number, entryOrder }

    init(seat: Binding<PassSeatInput>, isSaving: Bool, onSave: @escaping (PassSeatInput) -> Void) {
        _seat = seat
        self.isSaving = isSaving
        self.onSave = onSave
        // 已经填过整理番号的默认停在站席，其余一律指定席
        _mode = State(initialValue: seat.wrappedValue.entryOrder.isEmpty ? .reserved : .standing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("入场方式", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("ブロック / 区域（可留空）", text: $seat.section)
                        .focused($focused, equals: .section)
                    if mode == .reserved {
                        TextField("列", text: $seat.row)
                            .focused($focused, equals: .row)
                        TextField("番号", text: $seat.number)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focused, equals: .number)
                    } else {
                        TextField("整理番号", text: $seat.entryOrder)
                            .focused($focused, equals: .entryOrder)
                    }
                } header: {
                    Text(mode == .reserved ? "几排几座" : "整理番号")
                } footer: {
                    Text(mode == .reserved
                         ? "例：ブロック「1階」、列「A」、番号「23」"
                         : "例：ブロック「A」、整理番号「142」。站席按号码顺序入场。")
                }

                Section("卡面预览") {
                    LabeledContent(preview.isEmpty ? "座席" : seat.displayLabel) {
                        Text(preview.isEmpty ? "未填写" : preview)
                            .foregroundStyle(preview.isEmpty ? .secondary : .primary)
                    }
                }

                Section {
                    Button("清除座位", role: .destructive) {
                        seat = PassSeatInput()
                        save()
                    }
                    .disabled(seat.isEmpty)
                } footer: {
                    Text("座位是你自己填的，不会被验证，也不能当入场凭证。")
                }
            }
            .navigationTitle("座位信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { save() }
                    }
                }
            }
            .onChange(of: mode) { _, new in
                // 切换入场方式时清掉另一种的字段，避免同时残留两套值
                if new == .reserved {
                    seat.entryOrder = ""
                } else {
                    seat.row = ""
                    seat.number = ""
                }
            }
        }
    }

    private var preview: String { seat.displayText }

    private func save() {
        focused = nil
        onSave(seat.normalized)
        dismiss()
    }
}
