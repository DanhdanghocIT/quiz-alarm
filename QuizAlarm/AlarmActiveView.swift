import SwiftUI

struct AlarmActiveView: View {
    @EnvironmentObject var store: AlarmStore

    private enum FlowStep {
        case qrScan
        case quiz
    }

    private enum QuestionPhase {
        case answering
        case selfGrading       // Dành cho thẻ 2 mặt khi gõ chưa khớp
        case wrongRevealed     // Dành cho điền chỗ trống gõ sai hoặc khi bấm "Không nhớ"
    }

    @State private var step: FlowStep = .quiz
    @State private var queue: [Card] = []
    @State private var correctCount: Int = 0
    @State private var requiredTotal: Int = 3

    @State private var userInput: String = ""
    @State private var questionPhase: QuestionPhase = .answering
    @State private var qrErrorText: String? = nil
    @State private var cameraPermissionDenied: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                switch step {
                case .qrScan:
                    qrScanSection
                case .quiz:
                    quizSection
                }
            }
            .navigationTitle(store.isTestMode ? "Thử Báo Thức" : "Báo Thức Đang Kêu!")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            setupInitialSession()
            store.startAlarmAudio()
        }
    }

    private func setupInitialSession() {
        requiredTotal = min(max(store.settings.requiredCorrect, 1), 5)
        correctCount = 0
        queue = store.selectQuizQueue()
        userInput = ""
        questionPhase = .answering

        if store.settings.qrEnabled {
            step = .qrScan
        } else {
            step = .quiz
        }
    }

    // MARK: - Màn hình quét QR

    private var qrScanSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)

                Text("Quét mã QR để bắt đầu làm Quiz")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text("Hãy di chuyển đến nơi bạn dán mã QR và hướng camera vào mã.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if cameraPermissionDenied {
                VStack(spacing: 12) {
                    Text("Không có quyền truy cập Camera.")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Hãy cấp quyền Camera trong Cài đặt iPhone hoặc nhấn tiếp tục bên dưới.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Chuyển sang làm Quiz") {
                        step = .quiz
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                QRScannerRepresentable(
                    onCodeScanned: { scanned in
                        let cleanScanned = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanTarget = store.settings.qrCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleanScanned == cleanTarget {
                            qrErrorText = nil
                            step = .quiz
                        } else {
                            qrErrorText = "Mã QR không khớp! Hãy quét đúng mã QR của Quiz Alarm."
                        }
                    },
                    onPermissionDenied: {
                        cameraPermissionDenied = true
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red, lineWidth: 3)
                )
                .padding(.horizontal)
            }

            if let qrErrorText = qrErrorText {
                Text(qrErrorText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            if store.isTestMode {
                Button {
                    step = .quiz
                } label: {
                    Label("Bỏ qua quét QR (Chế độ thử)", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Màn hình làm Quiz

    @ViewBuilder
    private var quizSection: some View {
        if store.cards.isEmpty {
            emptyCardsView
        } else if let currentCard = queue.first {
            let parsed = ParsedQuestion.parse(from: currentCard)
            activeCardQuizView(card: currentCard, parsed: parsed)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Đã hoàn thành đủ câu hỏi!")
                    .font(.title2.bold())
                Button("Tắt báo thức") {
                    store.completeAlarm()
                }
                .buttonStyle(.borderedProminent)
            }
            .onAppear {
                store.completeAlarm()
            }
        }
    }

    private var emptyCardsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Chưa có thẻ học nào!")
                .font(.title2.bold())

            Text("Bạn chưa có thẻ nào trong ứng dụng. Hãy tắt báo thức và thêm thẻ mới ở tab \"Thẻ\" để sử dụng cho lần báo thức tiếp theo.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                store.completeAlarm()
            } label: {
                Text("Tắt báo thức")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
        }
    }

    private func activeCardQuizView(card: Card, parsed: ParsedQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Thanh tiến độ
                VStack(spacing: 6) {
                    HStack {
                        Text("Tiến độ: \(correctCount) / \(requiredTotal) câu đúng")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Còn \(queue.count) câu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(correctCount), total: Double(requiredTotal))
                        .tint(.green)
                }
                .padding(.horizontal)

                // Khung câu hỏi
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(parsed.isCloze ? "ĐIỀN CHỖ TRỐNG" : "THẺ HAI MẶT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(parsed.isCloze ? .purple : .blue)
                        Spacer()
                        Text("Box \(card.box)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Text(parsed.displayPrompt)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Khu vực trả lời / chấm điểm
                switch questionPhase {
                case .answering:
                    answeringControls(card: card, parsed: parsed)

                case .selfGrading:
                    selfGradingControls(card: card, parsed: parsed)

                case .wrongRevealed:
                    wrongRevealedControls(card: card, parsed: parsed)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func answeringControls(card: Card, parsed: ParsedQuestion) -> some View {
        VStack(spacing: 16) {
            TextField(
                parsed.isCloze ? "Nhập từ còn thiếu..." : "Nhập đáp án của bạn...",
                text: $userInput
            )
            .textFieldStyle(.roundedBorder)
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($isInputFocused)
            .submitLabel(.done)
            .onSubmit {
                submitTypedAnswer(card: card, parsed: parsed)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    isInputFocused = false
                    questionPhase = .wrongRevealed
                } label: {
                    Text("Không nhớ")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    isInputFocused = false
                    submitTypedAnswer(card: card, parsed: parsed)
                } label: {
                    Text("Kiểm tra")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
        }
    }

    private func selfGradingControls(card: Card, parsed: ParsedQuestion) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Câu trả lời của bạn:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(userInput)
                    .font(.body.weight(.medium))

                Divider()

                Text("Đáp án trên thẻ:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(parsed.rawAnswer)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            Text("Câu trả lời của bạn chưa khớp hoàn toàn. Hãy tự chấm:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    handleResult(card: card, isCorrect: false)
                } label: {
                    Label("Sai", systemImage: "xmark.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    handleResult(card: card, isCorrect: true)
                } label: {
                    Label("Đúng ý", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.horizontal)
        }
    }

    private func wrongRevealedControls(card: Card, parsed: ParsedQuestion) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Bạn đã nhập:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(userInput)
                        .font(.body)
                        .foregroundStyle(.red)
                    Divider()
                }

                Text("Đáp án đúng:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(parsed.rawAnswer)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)

                if parsed.isCloze && !card.back.isEmpty {
                    Divider()
                    Text("Ghi chú mặt sau:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.back)
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            Button {
                handleResult(card: card, isCorrect: false)
            } label: {
                Text("Tiếp tục")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
    }

    private func submitTypedAnswer(card: Card, parsed: ParsedQuestion) {
        if parsed.matches(userInput) {
            handleResult(card: card, isCorrect: true)
        } else {
            if parsed.isCloze {
                questionPhase = .wrongRevealed
            } else {
                questionPhase = .selfGrading
            }
        }
    }

    private func handleResult(card: Card, isCorrect: Bool) {
        if !store.isTestMode {
            store.recordCardAnswer(cardID: card.id, isCorrect: isCorrect)
        }

        guard !queue.isEmpty else {
            store.completeAlarm()
            return
        }

        let current = queue.removeFirst()

        if isCorrect {
            correctCount += 1
        } else {
            // Đưa câu sai xuống cuối hàng đợi
            queue.append(current)
        }

        userInput = ""
        questionPhase = .answering

        if correctCount >= requiredTotal || queue.isEmpty {
            store.completeAlarm()
        }
    }
}