import Foundation
import SwiftUI
import AVFoundation
import UserNotifications
import UIKit

@MainActor
final class AlarmStore: ObservableObject {
    @Published var settings: AlarmSettings = AlarmSettings()
    @Published var cards: [Card] = []

    @Published var isAlarmPresented: Bool = false
    @Published var isTestMode: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private let settingsFilename = "quiz_alarm_settings.json"
    private let cardsFilename = "quiz_alarm_cards.json"

    init() {
        loadSettings()
        loadCards()
        setupAudioInterruptionObserver()
    }

    // MARK: - Đường dẫn lưu trữ JSON trong Documents

    private func documentsURL(for filename: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(filename)
    }

    func loadSettings() {
        let url = documentsURL(for: settingsFilename)
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AlarmSettings.self, from: data) {
            var fixed = decoded
            fixed.requiredCorrect = min(max(fixed.requiredCorrect, 1), 5)
            if fixed.qrCode.isEmpty {
                fixed.qrCode = "QA-\(UUID().uuidString)"
            }
            self.settings = fixed
        }
    }

    func saveSettings() {
        let url = documentsURL(for: settingsFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    func loadCards() {
        let url = documentsURL(for: cardsFilename)
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Card].self, from: data) {
            self.cards = decoded
        }
    }

    func saveCards() {
        let url = documentsURL(for: cardsFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cards) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    // MARK: - Cập nhật cài đặt báo thức

    func setAlarmEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        if enabled {
            settings.lastSolved = Date()
        }
        saveSettings()
        rescheduleBackupNotifications()
    }

    func setAlarmTime(hour: Int, minute: Int) {
        guard settings.hour != hour || settings.minute != minute else { return }
        settings.hour = hour
        settings.minute = minute
        settings.lastSolved = Date()
        saveSettings()
        rescheduleBackupNotifications()
    }

    func setRequiredCorrect(_ count: Int) {
        settings.requiredCorrect = min(max(count, 1), 5)
        saveSettings()
        rescheduleBackupNotifications()
    }

    func setQREnabled(_ enabled: Bool) {
        settings.qrEnabled = enabled
        if settings.qrCode.isEmpty {
            settings.qrCode = "QA-\(UUID().uuidString)"
        }
        saveSettings()
        rescheduleBackupNotifications()
    }

    func regenerateQRCode() {
        settings.qrCode = "QA-\(UUID().uuidString)"
        saveSettings()
    }

    // MARK: - Tính toán thời điểm báo thức & Kích hoạt

    /// Lần gần nhất của giờ:phút đã đặt mà <= now
    func lastOccurrence(at now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = settings.hour
        components.minute = settings.minute
        components.second = 0

        let todayCandidate = calendar.date(from: components) ?? now
        if todayCandidate <= now {
            return todayCandidate
        } else {
            return calendar.date(byAdding: .day, value: -1, to: todayCandidate)
                ?? todayCandidate.addingTimeInterval(-86400)
        }
    }

    /// Lần tiếp theo của giờ:phút đã đặt (> now)
    func nextOccurrence(at now: Date = Date()) -> Date {
        let last = lastOccurrence(at: now)
        return Calendar.current.date(byAdding: .day, value: 1, to: last)
            ?? last.addingTimeInterval(86400)
    }

    func needsToSolveAlarm(at now: Date = Date()) -> Bool {
        guard settings.isEnabled else { return false }
        let lastOcc = lastOccurrence(at: now)
        let diff = now.timeIntervalSince(lastOcc)
        return settings.lastSolved < lastOcc && diff >= 0 && diff < 3 * 3600
    }

    func handleAppBecameActive() {
        let now = Date()
        if !isAlarmPresented && needsToSolveAlarm(at: now) {
            isTestMode = false
            isAlarmPresented = true
            startAlarmAudio()
        }
        rescheduleBackupNotifications(at: now)
    }

    func triggerTestAlarm() {
        isTestMode = true
        isAlarmPresented = true
        startAlarmAudio()
    }

    func completeAlarm() {
        stopAlarmAudio()
        let wasTest = isTestMode
        isAlarmPresented = false
        isTestMode = false

        if !wasTest {
            settings.lastSolved = Date()
            saveSettings()
        }
        rescheduleBackupNotifications()
    }

    // MARK: - Âm thanh báo thức & Idle Timer

    func startAlarmAudio() {
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }

        if let player = audioPlayer, player.isPlaying {
            return
        }

        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
            print("Không tìm thấy alarm.wav trong Bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            print("AVAudioPlayer error: \(error)")
        }
    }

    func stopAlarmAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        UIApplication.shared.isIdleTimerDisabled = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("AVAudioSession deactivate error: \(error)")
        }
    }

    private func setupAudioInterruptionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard self.isAlarmPresented else { return }
                if let typeValue = typeValue,
                   let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                   type == .ended {
                    self.startAlarmAudio()
                }
            }
        }
    }

    // MARK: - Thông báo cục bộ dự phòng (15 thông báo, mỗi phút 1 cái)

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in
                self.rescheduleBackupNotifications()
            }
        }
    }

    func rescheduleBackupNotifications(at now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        guard settings.isEnabled else { return }

        let lastOcc = lastOccurrence(at: now)
        let currentlyNeedsSolve = needsToSolveAlarm(at: now)

        // Nếu đang cần giải: bắt đầu từ max(lastOccurrence + 1 phút, bây giờ + 1 phút)
        // Nếu đã giải / đang đợi kỳ báo thức kế tiếp: đặt cho kỳ báo thức sắp tới (lúc đó sẽ là lastOccurrence + 1..15 phút)
        let baseReference: Date
        if currentlyNeedsSolve {
            baseReference = max(lastOcc, now)
        } else {
            baseReference = nextOccurrence(at: now)
        }

        let calendar = Calendar.current

        for minuteOffset in 1...15 {
            let fireDate = baseReference.addingTimeInterval(Double(minuteOffset * 60))
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Báo thức Quiz Alarm (\(minuteOffset)/15)"
            content.body = "Nhấn vào thông báo để mở ứng dụng và trả lời câu hỏi tắt báo thức!"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.wav"))
            content.interruptionLevel = .timeSensitive

            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let request = UNNotificationRequest(
                identifier: "quiz_alarm_backup_\(minuteOffset)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - Chọn thẻ cho bài Quiz & Cập nhật Spaced Repetition

    func selectQuizQueue() -> [Card] {
        guard !cards.isEmpty else { return [] }
        let now = Date()
        let twoDaysSeconds: TimeInterval = 2 * 86400
        let countNeeded = min(max(settings.requiredCorrect, 1), 5)

        // Xáo trộn trước để khi các tiêu chí bằng nhau thì thứ tự là ngẫu nhiên
        let shuffled = cards.shuffled()

        let sorted = shuffled.sorted { a, b in
            let aDue = a.due <= now
            let bDue = b.due <= now
            if aDue != bDue {
                return aDue && !bDue
            }

            let aRecent = now.timeIntervalSince(a.added) <= twoDaysSeconds
            let bRecent = now.timeIntervalSince(b.added) <= twoDaysSeconds
            if aRecent != bRecent {
                return aRecent && !bRecent
            }

            if a.box != b.box {
                return a.box < b.box
            }

            return false
        }

        var result: [Card] = []
        while result.count < countNeeded {
            for card in sorted {
                result.append(card)
                if result.count == countNeeded {
                    break
                }
            }
        }
        return result
    }

    func recordCardAnswer(cardID: UUID, isCorrect: Bool) {
        guard let idx = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let now = Date()

        if isCorrect {
            let newBox = min(cards[idx].box + 1, 5)
            cards[idx].box = newBox
            let intervalDays = Card.boxIntervalsDays[newBox]
            cards[idx].due = Calendar.current.date(byAdding: .day, value: intervalDays, to: now)
                ?? now.addingTimeInterval(Double(intervalDays) * 86400)
        } else {
            cards[idx].box = 0
            cards[idx].due = now
            cards[idx].wrong += 1
        }

        saveCards()
    }

    // MARK: - Quản lý Thẻ (Thêm / Sửa / Xóa / Nhập CSV-TXT)

    func addCard(front: String, back: String) {
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFront.isEmpty else { return }

        let now = Date()
        let newCard = Card(
            front: trimmedFront,
            back: trimmedBack,
            added: now,
            due: now,
            box: 0,
            wrong: 0
        )
        cards.insert(newCard, at: 0)
        saveCards()
    }

    func updateCard(_ updated: Card) {
        guard let idx = cards.firstIndex(where: { $0.id == updated.id }) else { return }
        cards[idx] = updated
        saveCards()
    }

    func deleteCards(at offsets: IndexSet) {
        cards.remove(atOffsets: offsets)
        saveCards()
    }

    func deleteCard(id: UUID) {
        cards.removeAll { $0.id == id }
        saveCards()
    }

    func deleteAllCards() {
        cards.removeAll()
        saveCards()
    }

    struct ImportSummary {
        let addedCount: Int
        let skippedDuplicates: Int
    }

    func importCards(from url: URL) throws -> ImportSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        var rawText = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)

        // Bỏ BOM nếu có
        if rawText.hasPrefix("\u{FEFF}") {
            rawText.removeFirst()
        }

        let delimiter = Self.detectDelimiter(in: rawText)
        let rows = Self.parseDelimitedText(rawText, delimiter: delimiter)

        var existingKeys = Set(cards.map { Self.dedupKey(front: $0.front, back: $0.back) })
        var addedCount = 0
        var skippedCount = 0
        let now = Date()

        for (rowIndex, row) in rows.enumerated() {
            guard row.count >= 2 else { continue }
            let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if front.isEmpty { continue }

            // Bỏ qua dòng tiêu đề nếu file có header chuẩn
            if rowIndex == 0 {
                let lowerFront = front.lowercased()
                let lowerBack = back.lowercased()
                if (lowerFront == "front" && lowerBack == "back") ||
                   (lowerFront == "mặt trước" && lowerBack == "mặt sau") {
                    continue
                }
            }

            let key = Self.dedupKey(front: front, back: back)
            if existingKeys.contains(key) {
                skippedCount += 1
                continue
            }

            existingKeys.insert(key)
            let card = Card(
                front: front,
                back: back,
                added: now,
                due: now,
                box: 0,
                wrong: 0
            )
            cards.append(card)
            addedCount += 1
        }

        if addedCount > 0 {
            saveCards()
        }

        return ImportSummary(addedCount: addedCount, skippedDuplicates: skippedCount)
    }

    private static func dedupKey(front: String, back: String) -> String {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(f)\u{001F}\(b)"
    }

    private static func detectDelimiter(in text: String) -> Character {
        let firstNonEmptyLine = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""

        var inQuotes = false
        var tabCount = 0
        var commaCount = 0

        for char in firstNonEmptyLine {
            if char == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if char == "\t" {
                    tabCount += 1
                } else if char == "," {
                    commaCount += 1
                }
            }
        }

        return (tabCount > 0 && tabCount >= commaCount) ? "\t" : ","
    }

    private static func parseDelimitedText(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0
        let count = chars.count

        while i < count {
            let ch = chars[i]

            if inQuotes {
                if ch == "\"" {
                    if i + 1 < count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.append(ch)
                    i += 1
                }
            } else {
                if ch == "\"" && currentField.trimmingCharacters(in: .whitespaces).isEmpty {
                    currentField = ""
                    inQuotes = true
                    i += 1
                } else if ch == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                    i += 1
                } else if ch.isNewline {
                    currentRow.append(currentField)
                    if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                    i += 1
                } else {
                    currentField.append(ch)
                    i += 1
                }
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }
}