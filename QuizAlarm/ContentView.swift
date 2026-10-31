import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            AlarmSettingsTabView()
                .tabItem {
                    Label("Báo thức", systemImage: "alarm.fill")
                }

            CardsTabView()
                .tabItem {
                    Label("Thẻ", systemImage: "rectangle.stack.fill")
                }
        }
    }
}

// MARK: - Tab 1: Báo thức

struct AlarmSettingsTabView: View {
    @EnvironmentObject var store: AlarmStore

    private var alarmDateBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = store.settings.hour
                comps.minute = store.settings.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.setAlarmTime(hour: comps.hour ?? 7, minute: comps.minute ?? 0)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { store.settings.isEnabled },
            set: { store.setAlarmEnabled($0) }
        )
    }

    private var requiredCorrectBinding: Binding<Int> {
        Binding<Int>(
            get: { store.settings.requiredCorrect },
            set: { store.setRequiredCorrect($0) }
        )
    }

    private var qrEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { store.settings.qrEnabled },
            set: { store.setQREnabled($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cài đặt báo thức") {
                    Toggle("Bật báo thức Quiz", isOn: enabledBinding)
                        .fontWeight(.semibold)

                    DatePicker(
                        "Giờ báo thức",
                        selection: alarmDateBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .center)

                    Stepper(
                        "Số câu phải đúng: \(store.settings.requiredCorrect)",
                        value: requiredCorrectBinding,
                        in: 1...5
                    )
                }

                Section {
                    Toggle("Yêu cầu quét mã QR trước khi làm Quiz", isOn: qrEnabledBinding)

                    if let qrUIImage = QRCodeGenerator.generateUIImage(from: store.settings.qrCode) {
                        VStack(spacing: 12) {
                            Image(uiImage: qrUIImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 2)

                            Text(store.settings.qrCode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 16) {
                                Button {
                                    store.regenerateQRCode()
                                } label: {
                                    Label("Tạo mã QR", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)

                                if let pngData = qrUIImage.pngData() {
                                    ShareLink(
                                        item: QRCodeShareItem(pngData: pngData),
                                        preview: SharePreview(
                                            "Mã QR Quiz Alarm",
                                            image: Image(uiImage: qrUIImage)
                                        )
                                    ) {
                                        Label("Chia sẻ / In QR", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Mã QR (Dán ở nhà tắm / bàn học)")
                } footer: {
                    Text("Khi bật, bạn phải dùng camera quét đúng mã QR này trước khi làm câu hỏi để tắt báo thức.")
                }

                Section("Kiểm tra") {
                    Button {
                        store.triggerTestAlarm()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Thử báo thức ngay")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Section("Hướng dẫn tạo Tự động hóa trong Phím tắt") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Để iPhone tự mở Quiz Alarm ngay khi báo thức kêu:")
                            .font(.subheadline.bold())

                        Group {
                            Text("1. Mở ứng dụng **Đồng hồ** của iPhone và đặt báo thức đúng giờ bạn đã chọn ở trên.")
                            Text("2. Mở ứng dụng **Phím tắt (Shortcuts)** → chọn tab **Tự động hóa (Automation)** ở dưới cùng.")
                            Text("3. Nhấn dấu **+** ở góc trên bên phải → chọn mục **Báo thức (Alarm)**.")
                            Text("4. Chọn **Bị dừng (Is Stopped)** (hoặc tạo thêm 1 tự động hóa nữa cho **Được báo lại / Is Snoozed**), mục Báo thức chọn **Bất kỳ (Any)** hoặc **Hiện có (Existing)**, và chọn **Chạy ngay lập tức (Run Immediately)** → nhấn **Tiếp (Next)**.")
                            Text("5. Chọn **Tự động hóa trống mới (New Blank Automation)** → tìm hành động **Mở ứng dụng (Open App)**.")
                            Text("6. Nhấn vào chữ **Ứng dụng (App)** màu xanh và chọn **Quiz Alarm** → nhấn **Xong (Done)**.")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Quiz Alarm")
        }
    }
}

// MARK: - Tab 2: Thẻ

struct CardsTabView: View {
    @EnvironmentObject var store: AlarmStore

    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var editingCard: Card? = nil
    @State private var showingFileImporter: Bool = false
    @State private var showingDeleteAllConfirm: Bool = false

    @State private var importAlertTitle: String = ""
    @State private var importAlertMessage: String = ""
    @State private var showingImportAlert: Bool = false

    private var filteredCards: [Card] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.cards }
        let norm = query.normalizedForQuiz()
        return store.cards.filter {
            $0.front.normalizedForQuiz().contains(norm) ||
            $0.back.normalizedForQuiz().contains(norm)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty {
                    ContentUnavailableView {
                        Label("Chưa có thẻ nào", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Hãy thêm thẻ mới hoặc nhập từ file .csv / .txt để sử dụng khi báo thức kêu.")
                    } actions: {
                        HStack(spacing: 12) {
                            Button("Thêm thẻ") {
                                showingAddSheet = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Nhập file CSV/TXT") {
                                showingFileImporter = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    List {
                        ForEach(filteredCards) { card in
                            Button {
                                editingCard = card
                            } label: {
                                CardRowView(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let idsToDelete = offsets.map { filteredCards[$0].id }
                            for id in idsToDelete {
                                store.deleteCard(id: id)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Tìm kiếm thẻ...")
                }
            }
            .navigationTitle("Thẻ (\(store.cards.count))")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Nhập file (.csv / .txt)", systemImage: "square.and.arrow.down")
                        }

                        if !store.cards.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteAllConfirm = true
                            } label: {
                                Label("Xóa tất cả thẻ", systemImage: "trash")
                            }
                        }
                    } label: {
                        Label("Tùy chọn", systemImage: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Thêm thẻ", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                CardEditorSheet(mode: .add) { front, back in
                    store.addCard(front: front, back: back)
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditorSheet(mode: .edit(card)) { front, back in
                    var updated = card
                    updated.front = front
                    updated.back = back
                    store.updateCard(updated)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [
                    .commaSeparatedText,
                    .tabSeparatedText,
                    .plainText,
                    .text,
                    .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let firstURL = urls.first else { return }
                    do {
                        let summary = try store.importCards(from: firstURL)
                        importAlertTitle = "Nhập file thành công"
                        importAlertMessage = "Đã thêm \(summary.addedCount) thẻ mới.\nBỏ qua \(summary.skippedDuplicates) thẻ trùng."
                        showingImportAlert = true
                    } catch {
                        importAlertTitle = "Lỗi nhập file"
                        importAlertMessage = error.localizedDescription
                        showingImportAlert = true
                    }
                case .failure(let error):
                    importAlertTitle = "Lỗi chọn file"
                    importAlertMessage = error.localizedDescription
                    showingImportAlert = true
                }
            }
            .alert(importAlertTitle, isPresented: $showingImportAlert) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(importAlertMessage)
            }
            .confirmationDialog(
                "Bạn có chắc chắn muốn xóa toàn bộ \(store.cards.count) thẻ?",
                isPresented: $showingDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Xóa tất cả", role: .destructive) {
                    store.deleteAllCards()
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}

struct CardRowView: View {
    let card: Card

    private var isCloze: Bool {
        ParsedQuestion.parse(from: card).isCloze
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isCloze ? "Điền chỗ trống" : "Hai mặt")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isCloze ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                    .foregroundStyle(isCloze ? Color.purple : Color.blue)
                    .clipShape(Capsule())

                Spacer()

                Text("Box \(card.box)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                if card.wrong > 0 {
                    Text("• Sai \(card.wrong)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text(card.front)
                .font(.body.weight(.medium))
                .lineLimit(2)

            if !card.back.isEmpty {
                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            let isDue = card.due <= Date()
            Text(
                isDue
                    ? "Đến hạn ôn tập"
                    : "Đến hạn: \(card.due.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption2)
            .foregroundStyle(isDue ? .orange : .secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CardEditorSheet: View {
    enum Mode {
        case add
        case edit(Card)
    }

    let mode: Mode
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var front: String = ""
    @State private var back: String = ""

    init(mode: Mode, onSave: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _front = State(initialValue: "")
            _back = State(initialValue: "")
        case .edit(let card):
            _front = State(initialValue: card.front)
            _back = State(initialValue: card.back)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mặt trước (Câu hỏi)") {
                    TextField("Nhập câu hỏi hoặc câu có {{từ khóa}}...", text: $front, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Mặt sau (Đáp án / Ghi chú)") {
                    TextField("Nhập đáp án (ngăn cách nhiều đáp án bằng |)...", text: $back, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Mẹo định dạng") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **Thẻ hai mặt**: Nhập câu hỏi ở Mặt trước, đáp án ở Mặt sau. Có thể nhập nhiều đáp án đúng cách nhau bởi dấu `|` (ví dụ: `xin chào | chào bạn`).")
                        Text("• **Điền chỗ trống**: Bao từ cần điền trong `{{...}}` ở Mặt trước (ví dụ: `Thủ đô của Việt Nam là {{Hà Nội}}`).")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEdit ? "Sửa thẻ" : "Thêm thẻ mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(
                            front.trimmingCharacters(in: .whitespacesAndNewlines),
                            back.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }
}