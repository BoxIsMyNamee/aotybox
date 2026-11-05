import SwiftUI
import UIKit

/// Proof: paste a review you wrote elsewhere and get proofreading notes.
/// It never rewrites the review. Repeated words are counted on-device (exact);
/// typos, punctuation, run-ons and comma issues come from the AI as pointers only.
struct ProofView: View {
    @AppStorage("proofDraft") private var text = ""
    @State private var report: ProofReport?
    @State private var rawReply: String?
    @State private var stats: ProofStats?
    @State private var checking = false
    @State private var error: String?
    @State private var showAISettings = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste your review here…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: $text)
                            .focused($editing)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                    }
                    HStack {
                        Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                        if !text.isEmpty {
                            Button(role: .destructive) { text = ""; report = nil; stats = nil; rawReply = nil; error = nil } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        if !text.isEmpty {
                            Text("\(ProofStats.words(in: text).count) words").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Proof only points things out. It never rewrites your review.")
                }

                Section {
                    Button { Task { await check() } } label: {
                        HStack {
                            Spacer()
                            if checking { ProgressView().padding(.trailing, 6); Text("Checking…") }
                            else { Label("Check review", systemImage: "text.badge.checkmark").bold() }
                            Spacer()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                    if !AISettings.isConfigured {
                        Button("Set up the AI (Gemini is free)") { showAISettings = true }
                            .font(.footnote)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                if let stats { statsSections(stats) }

                if let report {
                    if let s = report.summary, !s.isEmpty {
                        Section { Text(s).font(.callout) }
                    }
                    issueSection("Typos & spelling", "character.cursor.ibeam", report.typos + (stats?.doubled ?? []))
                    issueSection("Punctuation", "exclamationmark.questionmark", report.punctuation)
                    issueSection("Run-on sentences", "arrow.right.to.line", report.runOns)
                    issueSection("Commas", "comma", report.commas)
                    issueSection("Grammar & wording", "text.magnifyingglass", report.other)
                    if report.isEmpty && (stats?.doubled ?? []).isEmpty {
                        Section { Label("No problems found.", systemImage: "checkmark.seal").foregroundStyle(.green) }
                    }
                } else if let rawReply {
                    Section("Notes") { Text(LocalizedStringKey(rawReply)).textSelection(.enabled) }
                }
            }
            .navigationTitle("Proof")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .sheet(isPresented: $showAISettings) { NavigationStack { AISettingsView() }.accentTint() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func statsSections(_ s: ProofStats) -> some View {
        Section("Overview") {
            LabeledContent("Words", value: "\(s.wordCount)")
            LabeledContent("Sentences", value: "\(s.sentenceCount)")
            LabeledContent("Average sentence", value: "\(s.averageSentence) words")
            if let longest = s.longest, longest.count >= 35 {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Longest sentence", value: "\(longest.count) words")
                    Text("“\(longest.preview)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        if !s.repeated.isEmpty {
            Section {
                FlowChips(items: s.repeated.map { "\($0.word) ×\($0.count)" })
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("Repeated words")
            } footer: {
                Text("Words used 3+ times, leaving out common ones like “the” and “and”.")
            }
        }
    }

    @ViewBuilder
    private func issueSection(_ title: String, _ icon: String, _ items: [ProofIssue]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        if !i.text.isEmpty {
                            Text("“\(i.text)”").font(.callout.weight(.medium)).textSelection(.enabled)
                        }
                        if let sug = i.suggestion, !sug.isEmpty {
                            Text("→ \(sug)").font(.callout).foregroundStyle(.tint)
                        }
                        if !i.note.isEmpty {
                            Text(i.note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("\(title) · \(items.count)", systemImage: icon)
            }
        }
    }

    // MARK: Actions

    private func paste() {
        if let s = UIPasteboard.general.string, !s.isEmpty {
            text = s; report = nil; stats = nil; rawReply = nil; error = nil
        }
    }

    private func check() async {
        let review = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !review.isEmpty else { return }
        editing = false
        error = nil; report = nil; rawReply = nil
        stats = ProofStats(review)
        guard AISettings.isConfigured else {
            error = "Repeated words are counted above. For typo and punctuation notes, set up the AI."
            return
        }
        checking = true; defer { checking = false }
        do {
            let reply = try await AIClient.reply(system: ProofReport.systemPrompt,
                                                 history: [ChatMessage(role: .user, text: review)],
                                                 webSearch: false)
            if let r = ProofReport.parse(reply.text) { report = r } else { rawReply = reply.text }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - AI report

struct ProofIssue: Decodable, Identifiable, Hashable {
    let id = UUID()
    let text: String
    let suggestion: String?
    let note: String

    enum CodingKeys: String, CodingKey { case text, suggestion, note }
    init(text: String, suggestion: String?, note: String) { self.text = text; self.suggestion = suggestion; self.note = note }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        suggestion = try? c.decode(String.self, forKey: .suggestion)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

struct ProofReport: Decodable {
    var summary: String?
    var typos: [ProofIssue] = []
    var punctuation: [ProofIssue] = []
    var runOns: [ProofIssue] = []
    var commas: [ProofIssue] = []
    var other: [ProofIssue] = []

    var isEmpty: Bool { typos.isEmpty && punctuation.isEmpty && runOns.isEmpty && commas.isEmpty && other.isEmpty }

    enum CodingKeys: String, CodingKey { case summary, typos, punctuation, runOns, commas, other }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        summary = try? c.decode(String.self, forKey: .summary)
        typos = (try? c.decode([ProofIssue].self, forKey: .typos)) ?? []
        punctuation = (try? c.decode([ProofIssue].self, forKey: .punctuation)) ?? []
        runOns = (try? c.decode([ProofIssue].self, forKey: .runOns)) ?? []
        commas = (try? c.decode([ProofIssue].self, forKey: .commas)) ?? []
        other = (try? c.decode([ProofIssue].self, forKey: .other)) ?? []
    }

    static func parse(_ reply: String) -> ProofReport? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}") else { return nil }
        return try? JSONDecoder().decode(ProofReport.self, from: Data(reply[start...end].utf8))
    }

    static let systemPrompt = """
    You are a proofreader for music reviews. The user pastes a review they wrote. Your only job is to \
    point out mechanical problems. You must NEVER rewrite, rephrase, improve, or return the review or any \
    full corrected sentence. Do not comment on opinions, tone, structure, or content.

    Look only for:
    - typos: misspellings, wrong word (their/there, its/it's), missing or extra letters. Give the correct \
      spelling of just that word as "suggestion".
    - punctuation: missing or wrong apostrophes, quotes, periods, question marks, stray or doubled \
      punctuation, spacing around punctuation, mismatched parentheses.
    - runOns: run-on sentences and comma splices. Quote only the first few words of the sentence and say \
      where a break could go (e.g. "after 'production'"). Do not write the fixed sentence.
    - commas: lingering or trailing commas, commas before a period, missing commas after introductory \
      phrases, commas that split a subject from its verb.
    - other: clear grammar slips (subject-verb agreement, wrong tense mid-sentence, missing words).

    Respect intentional style: deliberate lowercase, slang, album/artist stylizations, fragments used for \
    effect, and profanity are not errors. When unsure, leave it out.

    Reply with ONLY this JSON, no other text:
    {"summary": "one short sentence on overall mechanics",
     "typos": [{"text": "exact word or short phrase from the review", "suggestion": "correct spelling", "note": "short reason"}],
     "punctuation": [{"text": "exact short snippet", "note": "what's wrong"}],
     "runOns": [{"text": "first few words of the sentence", "note": "where it could break"}],
     "commas": [{"text": "exact short snippet", "note": "what's wrong"}],
     "other": [{"text": "exact short snippet", "note": "what's wrong"}]}
    Snippets must be copied exactly from the review and kept under 12 words. Use empty arrays when there is nothing.
    """
}

// MARK: - On-device stats

struct ProofStats {
    struct Repeat: Hashable { let word: String; let count: Int }
    let wordCount: Int
    let sentenceCount: Int
    let averageSentence: Int
    let longest: (count: Int, preview: String)?
    let repeated: [Repeat]
    let doubled: [ProofIssue]

    static func words(in s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    private static let common: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "of", "to", "in", "on", "at", "for", "with", "by", "from", "as",
        "is", "are", "was", "were", "be", "been", "being", "am", "it", "it's", "its", "this", "that", "these", "those",
        "i", "i'm", "me", "my", "you", "your", "he", "she", "his", "her", "they", "them", "their", "we", "our", "us",
        "not", "no", "so", "do", "does", "did", "have", "has", "had", "just", "than", "then", "there", "here", "what",
        "which", "who", "when", "where", "how", "all", "can", "will", "would", "could", "should", "into", "out", "up",
        "about", "more", "very", "also", "some", "one", "like", "don't", "can't", "isn't", "there's", "that's",
        "too", "much", "even", "only", "own", "over", "s", "t", "him",
    ]

    init(_ text: String) {
        let w = Self.words(in: text)
        wordCount = w.count
        let sentences = text
            .replacingOccurrences(of: #"([.!?…]+)(\s+|$)"#, with: "$1\u{1E}", options: .regularExpression)
            .split(separator: "\u{1E}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !Self.words(in: $0).isEmpty }
        sentenceCount = max(sentences.count, w.isEmpty ? 0 : 1)
        averageSentence = sentenceCount == 0 ? 0 : Int((Double(w.count) / Double(sentenceCount)).rounded())
        longest = sentences.map { (Self.words(in: $0).count, String($0.prefix(140)) + ($0.count > 140 ? "…" : "")) }.max { $0.0 < $1.0 }

        var counts: [String: Int] = [:]
        for word in w where word.count >= 3 && !Self.common.contains(word) { counts[word, default: 0] += 1 }
        repeated = counts.filter { $0.value >= 3 }
            .map { Repeat(word: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word < $1.word }
            .prefix(20).map { $0 }

        // "the the", "and and" — doubled words are almost always typos.
        var found: [ProofIssue] = []
        if let re = try? NSRegularExpression(pattern: #"\b([A-Za-z']+)\s+\1\b"#, options: .caseInsensitive) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let phrase = ns.substring(with: m.range)
                let word = ns.substring(with: m.range(at: 1)).lowercased()
                if ["ha", "no", "la", "na", "yeah", "very", "so", "bye", "hey", "go"].contains(word) { continue }
                found.append(ProofIssue(text: phrase, suggestion: nil, note: "Word typed twice in a row."))
            }
        }
        doubled = found
    }
}

/// Wrapping row of small capsule chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        ChipLayout(spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.callout.monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.tint.opacity(0.18), in: Capsule())
            }
        }
    }
}

struct ChipLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
