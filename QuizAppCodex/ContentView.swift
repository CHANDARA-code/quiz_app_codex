//
//  ContentView.swift
//  QuizAppCodex
//
//  Created by chandara-dgc on 4/3/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = QuizViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                QuizTheme.backgroundGradient
                    .ignoresSafeArea()

                Group {
                    if viewModel.isLoading {
                        LoadingView()
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorView(message: errorMessage) {
                            Task { await viewModel.loadQuiz() }
                        }
                    } else if viewModel.isQuizComplete {
                        ResultView(
                            score: viewModel.score,
                            total: viewModel.questions.count
                        ) {
                            Task { await viewModel.loadQuiz() }
                        }
                    } else if let question = viewModel.currentQuestion {
                        QuestionView(
                            question: question,
                            questionNumber: viewModel.currentIndex + 1,
                            totalQuestions: viewModel.questions.count,
                            selectedAnswer: viewModel.selectedAnswer,
                            score: viewModel.score,
                            onSelect: viewModel.selectAnswer
                        )
                        .id(viewModel.currentIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                        .safeAreaInset(edge: .bottom) {
                            BottomBar(
                                selectedAnswer: viewModel.selectedAnswer,
                                isLastQuestion: viewModel.isLastQuestion,
                                onNext: viewModel.nextQuestion
                            )
                        }
                    } else {
                        EmptyStateView {
                            Task { await viewModel.loadQuiz() }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .navigationTitle("Quiz Lab")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadQuizIfNeeded()
        }
    }
}

@MainActor
final class QuizViewModel: ObservableObject {
    @Published var questions: [QuizQuestion] = []
    @Published var currentIndex = 0
    @Published var selectedAnswer: String?
    @Published var score = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var hasLoaded = false

    private let quizURL = URL(string: "https://opentdb.com/api.php?amount=12&type=multiple")!

    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    var isQuizComplete: Bool {
        !questions.isEmpty && currentIndex >= questions.count
    }

    func loadQuizIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadQuiz()
    }

    func loadQuiz() async {
        isLoading = true
        errorMessage = nil
        selectedAnswer = nil
        currentIndex = 0
        score = 0

        do {
            let (data, response) = try await URLSession.shared.data(from: quizURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw QuizError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(TriviaResponse.self, from: data)
            guard decoded.responseCode == 0, !decoded.results.isEmpty else {
                throw QuizError.noQuestions
            }

            questions = decoded.results.map(QuizQuestion.init(dto:))
        } catch {
            errorMessage = "Could not load quiz questions. Please try again."
            questions = []
        }

        isLoading = false
    }

    func selectAnswer(_ answer: String) {
        guard selectedAnswer == nil, let question = currentQuestion else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedAnswer = answer
            if answer == question.correctAnswer {
                score += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    func nextQuestion() {
        guard selectedAnswer != nil else { return }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            selectedAnswer = nil
            currentIndex += 1
        }
    }
}

private enum QuizTheme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.14, blue: 0.28),
            Color(red: 0.04, green: 0.35, blue: 0.43),
            Color(red: 0.89, green: 0.45, blue: 0.21)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardFill = Color.white.opacity(0.16)
    static let cardStroke = Color.white.opacity(0.32)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.78)
    static let accent = Color(red: 0.99, green: 0.78, blue: 0.28)
}

struct LoadingView: View {
    @State private var spin = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 46))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(spin ? 8 : -8))
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: spin)

            Text("Loading your quiz...")
                .font(.headline)
                .foregroundStyle(QuizTheme.textPrimary)

            ProgressView()
                .tint(QuizTheme.accent)
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { spin = true }
    }
}

struct EmptyStateView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            GlassCard {
                VStack(spacing: 14) {
                    Text("Welcome to Quiz Lab")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(QuizTheme.textPrimary)

                    Text("12 random questions. Pick the best answer and chase a perfect score.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(QuizTheme.textSecondary)

                    Button("Start Quiz", action: onStart)
                        .buttonStyle(PrimaryCTAButtonStyle())
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuestionView: View {
    let question: QuizQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let selectedAnswer: String?
    let score: Int
    let onSelect: (String) -> Void

    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(questionNumber - 1) / Double(totalQuestions)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                topMeta

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(question.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuizTheme.textSecondary)

                        Text(question.question)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(QuizTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Badge(text: "Q\(questionNumber)/\(totalQuestions)")
                            Badge(text: question.difficulty.capitalized)
                        }
                    }
                    .padding(20)
                }

                VStack(spacing: 12) {
                    ForEach(Array(question.answers.enumerated()), id: \.element) { index, answer in
                        AnswerButton(
                            index: index,
                            answer: answer,
                            state: optionState(for: answer),
                            onTap: { onSelect(answer) }
                        )
                        .disabled(selectedAnswer != nil)
                    }
                }
            }
            .padding(.bottom, 90)
        }
    }

    private var topMeta: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score: \(score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuizTheme.textPrimary)

                Spacer()

                Text("Question \(questionNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuizTheme.textPrimary)
            }

            ProgressView(value: progress)
                .tint(QuizTheme.accent)
                .scaleEffect(x: 1, y: 1.8, anchor: .center)
        }
    }

    private func optionState(for answer: String) -> AnswerState {
        guard let selectedAnswer else { return .idle }

        if answer == question.correctAnswer {
            return answer == selectedAnswer ? .selectedCorrect : .revealedCorrect
        }

        if answer == selectedAnswer {
            return .selectedWrong
        }

        return .locked
    }
}

struct ResultView: View {
    let score: Int
    let total: Int
    let onRestart: () -> Void

    private var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(score) / Double(total) * 100).rounded())
    }

    private var summary: String {
        switch percentage {
        case 90...100: return "Excellent run"
        case 70...89: return "Great job"
        case 40...69: return "Solid effort"
        default: return "Try another round"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            GlassCard {
                VStack(spacing: 14) {
                    Text("Quiz Complete")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(QuizTheme.textPrimary)

                    Text("\(percentage)%")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(QuizTheme.accent)

                    Text("\(score) / \(total) correct")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(QuizTheme.textPrimary)

                    Text(summary)
                        .foregroundStyle(QuizTheme.textSecondary)

                    Button("Play Again", action: onRestart)
                        .buttonStyle(PrimaryCTAButtonStyle())
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack {
            GlassCard {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(QuizTheme.accent)

                    Text("Connection issue")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(QuizTheme.textPrimary)

                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(QuizTheme.textSecondary)

                    Button("Retry", action: onRetry)
                        .buttonStyle(PrimaryCTAButtonStyle())
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BottomBar: View {
    let selectedAnswer: String?
    let isLastQuestion: Bool
    let onNext: () -> Void

    var body: some View {
        HStack {
            Text(selectedAnswer == nil ? "Pick an answer" : "Answer locked")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer()

            Button(isLastQuestion ? "Finish" : "Next", action: onNext)
                .buttonStyle(PrimaryCTAButtonStyle())
                .disabled(selectedAnswer == nil)
                .opacity(selectedAnswer == nil ? 0.55 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.16), in: Capsule())
    }
}

enum AnswerState {
    case idle
    case selectedCorrect
    case revealedCorrect
    case selectedWrong
    case locked
}

struct AnswerButton: View {
    let index: Int
    let answer: String
    let state: AnswerState
    let onTap: () -> Void

    private var label: String {
        let letters = ["A", "B", "C", "D"]
        if index >= 0 && index < letters.count {
            return letters[index]
        }
        return "?"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuizTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.2), in: Circle())

                Text(answer)
                    .foregroundStyle(QuizTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let symbol = statusIcon {
                    Image(systemName: symbol)
                        .foregroundStyle(iconColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.6)
            )
        }
        .buttonStyle(PressScaleStyle())
    }

    private var background: Color {
        switch state {
        case .idle: return QuizTheme.cardFill
        case .selectedCorrect: return Color.green.opacity(0.30)
        case .revealedCorrect: return Color.green.opacity(0.22)
        case .selectedWrong: return Color.red.opacity(0.28)
        case .locked: return Color.white.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return QuizTheme.cardStroke
        case .selectedCorrect, .revealedCorrect: return Color.green.opacity(0.9)
        case .selectedWrong: return Color.red.opacity(0.9)
        case .locked: return Color.white.opacity(0.14)
        }
    }

    private var statusIcon: String? {
        switch state {
        case .selectedCorrect, .revealedCorrect: return "checkmark.circle.fill"
        case .selectedWrong: return "xmark.circle.fill"
        case .idle, .locked: return nil
        }
    }

    private var iconColor: Color {
        switch state {
        case .selectedCorrect, .revealedCorrect: return .green
        case .selectedWrong: return .red
        case .idle, .locked: return .clear
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(QuizTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(QuizTheme.cardStroke, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 8)
    }
}

struct PrimaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(QuizTheme.accent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct TriviaResponse: Decodable {
    let responseCode: Int
    let results: [TriviaQuestionDTO]

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case results
    }
}

struct TriviaQuestionDTO: Decodable {
    let category: String
    let difficulty: String
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]

    enum CodingKeys: String, CodingKey {
        case category
        case difficulty
        case question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
    }
}

struct QuizQuestion {
    let category: String
    let difficulty: String
    let question: String
    let correctAnswer: String
    let answers: [String]

    init(dto: TriviaQuestionDTO) {
        category = dto.category.htmlDecoded
        difficulty = dto.difficulty.htmlDecoded
        question = dto.question.htmlDecoded
        correctAnswer = dto.correctAnswer.htmlDecoded
        let wrongAnswers = dto.incorrectAnswers.map(\.htmlDecoded)
        answers = ([correctAnswer] + wrongAnswers).shuffled()
    }
}

enum QuizError: Error {
    case invalidResponse
    case noQuestions
}

extension String {
    var htmlDecoded: String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }

        return attributedString.string
    }
}

#Preview {
    ContentView()
}
