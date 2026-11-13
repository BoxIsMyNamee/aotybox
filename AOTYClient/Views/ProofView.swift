import SwiftUI
import UIKit

/// Notes: paste a review you wrote elsewhere and get proofreading notes. Never rewrites it.
/// Repeated words are counted on-device; typos, punctuation, run-ons, commas and unquoted
/// track names come from the AI (and an exact tracklist check when an album is given).
struct ProofView: View {
    @AppStorage("notesText") private var text = ""
    @AppStorage("notesAlbum") private var albumQuery = ""
    @AppStorage("notesAlbumCheck") private var albumCheckOn = false
    @State private var matchedAlbum: String?
    @State private var trackIssues: [ProofIssue] = []
    @State private var report: ProofReport?
    @State private var rawReply: String?
    @State private var stats: ProofStats?
    @State private var checking = false
    @State private var stage: String?
    @State private var job: Task<Void, Never>?
    @State private var error: String?
    @State private var copied = false
    @State private var showAISettings = false
    @FocusState private var focus: Field?
    private enum Field { case text, album }

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .notesImported)) { _ in resetResults() }
    }

    @ViewBuilder private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editor
                    if albumCheckOn { albumField }
                    if !AISettings.isConfigured {
                        Button("Set up the AI (Gemini is free)") { showAISettings = true }.font(.footnote)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    results
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .tabTitle("Notes")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .sheet(isPresented: $showAISettings) { NavigationStack { AISettingsView() }.accentTint() }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.isEmpty ? "Your review" : "\(ProofStats.words(in: text).count) words")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !text.isEmpty {
                    Button("Clear", role: .destructive) { text = ""; resetResults(); matchedAlbum = nil }
                        .font(.caption.weight(.semibold))
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($focus, equals: .text)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if text.isEmpty {
                    Text("Paste your review here…")
                        .font(.callout).foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 200)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button {
                    if let s = UIPasteboard.general.string, !s.isEmpty { text = s; resetResults() }
                } label: {
                    iconLabel("doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Paste")
                .frame(maxWidth: .infinity)

                Button {
                    if checking { job?.cancel(); job = nil; checking = false; stage = nil; return }
                    job = Task { await check() }
                } label: {
                    HStack(spacing: 6) {
                        if checking { ProgressView().tint(.white) }
                        Text(checking ? (stage ?? "Checking") : "Proof").bold()
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .buttonBorderShape(.capsule)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !checking)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    iconLabel(copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel(copied ? "Copied" : "Copy")
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(text.isEmpty)
                .frame(maxWidth: .infinity)
            }
            Text(checking ? "Tap again to stop." : "Proof only points things out. It never rewrites your review.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Same size and shape for Paste and Copy, whatever the icon.
    private func iconLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .frame(width: 24, height: 24)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentTransition(.symbolEffect(.replace))
    }

    private var albumField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Album (optional)").font(.caption).foregroundStyle(.secondary)
            TextField("e.g. the weeknd after hours", text: $albumQuery)
                .focused($focus, equals: .album)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: albumQuery) { matchedAlbum = nil }
            Text(matchedAlbum ?? "With an album, Proof checks that every track name you mention is in quotes, like 'blinding lights'.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if let stats { statsCards(stats) }
        if let report {
            if let s = report.summary, !s.isEmpty { card { Text(s).font(.callout) } }
            issueCard("Track names not in quotes", "quote.opening", mergedTrackIssues(report))
            issueCard("Typos & spelling", "character.cursor.ibeam", report.typos + (stats?.doubled ?? []))
            issueCard("Punctuation", "exclamationmark.questionmark", report.punctuation)
            issueCard("Run-on sentences", "arrow.right.to.line", report.runOns)
            issueCard("Commas", "comma", report.commas)
            issueCard("Grammar & wording", "text.magnifyingglass", report.other)
            if report.isEmpty && (stats?.doubled ?? []).isEmpty && trackIssues.isEmpty {
                card { Label("No problems found.", systemImage: "checkmark.seal").foregroundStyle(.green) }
            }
        } else {
            issueCard("Track names not in quotes", "quote.opening", trackIssues)
            issueCard("Typos & spelling", "character.cursor.ibeam", stats?.doubled ?? [])
            if let rawReply { card { Text(LocalizedStringKey(rawReply)).textSelection(.enabled) } }
        }
    }

    private func card<C: View>(_ title: String? = nil, _ icon: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: icon ?? "circle").font(.subheadline.weight(.semibold))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statsCards(_ s: ProofStats) -> some View {
        card("Overview", "chart.bar.doc.horizontal") {
            HStack {
                stat("\(s.wordCount)", "words"); stat("\(s.sentenceCount)", "sentences"); stat("\(s.averageSentence)", "avg length")
            }
            if let longest = s.longest, longest.count >= 35 {
                Text("Longest sentence: \(longest.count) words").font(.caption.weight(.semibold))
                Text("“\(longest.preview)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        if !s.repeated.isEmpty {
            card("Repeated words", "repeat") {
                FlowChips(items: s.repeated.map { "\($0.word) ×\($0.count)" })
                Text("Words used 3+ times, leaving out common ones like “the” and “and”.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func issueCard(_ title: String, _ icon: String, _ items: [ProofIssue]) -> some View {
        if !items.isEmpty {
            card("\(title) · \(items.count)", icon) {
                ForEach(items) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        if !i.text.isEmpty { Text("“\(i.text)”").font(.callout.weight(.medium)).textSelection(.enabled) }
                        if let sug = i.suggestion, !sug.isEmpty { Text("→ \(sug)").font(.callout).foregroundStyle(.green) }
                        if !i.note.isEmpty { Text(i.note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if i != items.last { Divider() }
                }
            }
        }
    }

    // MARK: Actions

    private func resetResults() { report = nil; stats = nil; rawReply = nil; error = nil; trackIssues = [] }

    private func mergedTrackIssues(_ r: ProofReport) -> [ProofIssue] {
        var seen = Set(trackIssues.map { $0.text.lowercased() })
        // Titles only mentioned in favs: / least favs: lines don't count.
        let body = ProofStats.withoutFavLines(text).lowercased()
        return trackIssues + r.trackNames.filter { body.contains($0.text.lowercased()) && seen.insert($0.text.lowercased()).inserted }
    }

    /// Runs `work`, giving up after `seconds` (the network request is cancelled too).
    private func within<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await work() }
            g.addTask { try await Task.sleep(for: .seconds(seconds)); throw CancellationError() }
            defer { g.cancelAll() }
            return try await g.next()!
        }
    }

    private func check() async {
        let review = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !review.isEmpty else { return }
        focus = nil
        error = nil; report = nil; rawReply = nil; trackIssues = []
        stats = ProofStats(review)
        checking = true
        defer { if !Task.isCancelled { checking = false; stage = nil; job = nil } }
        var tracklist: [String] = []
        let q = albumCheckOn ? albumQuery.trimmingCharacters(in: .whitespaces) : ""
        if !q.isEmpty {
            stage = "Finding album"
            if let found = try? await within(25, { await MusicAppLink.searchAlbum(q) }) {
                matchedAlbum = "Matched: \(found.title) by \(found.artist) · \(found.tracks.count) tracks"
                tracklist = found.tracks.map(\.title)
                trackIssues = ProofStats.unquotedTracks(in: ProofStats.withoutFavLines(review), tracks: tracklist)
            } else if !Task.isCancelled {
                matchedAlbum = "Couldn't find that album. Try \"artist album\" spelled like on AOTY."
            }
        }
        if Task.isCancelled { return }
        guard AISettings.isConfigured else {
            error = "Repeated words are counted above. For typo and punctuation notes, set up the AI."
            return
        }
        stage = "Proofing"
        let system = ProofReport.systemPrompt + (tracklist.isEmpty ? "" :
            "\n\nThe review is about an album with these tracks: " + tracklist.joined(separator: "; "))
        do {
            let reply = try await within(60) {
                try await AIClient.reply(system: system, history: [ChatMessage(role: .user, text: review)], webSearch: false)
            }
            if let r = ProofReport.parse(reply.text) { report = r } else { rawReply = reply.text }
        } catch is CancellationError {
            if !Task.isCancelled { self.error = "The AI didn't answer within a minute. It may be busy, so try again in a bit." }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }}

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
    var trackNames: [ProofIssue] = []

    var isEmpty: Bool { typos.isEmpty && punctuation.isEmpty && runOns.isEmpty && commas.isEmpty && other.isEmpty && trackNames.isEmpty }

    enum CodingKeys: String, CodingKey { case summary, typos, punctuation, runOns, commas, other, trackNames }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        summary = try? c.decode(String.self, forKey: .summary)
        typos = (try? c.decode([ProofIssue].self, forKey: .typos)) ?? []
        punctuation = (try? c.decode([ProofIssue].self, forKey: .punctuation)) ?? []
        runOns = (try? c.decode([ProofIssue].self, forKey: .runOns)) ?? []
        commas = (try? c.decode([ProofIssue].self, forKey: .commas)) ?? []
        other = (try? c.decode([ProofIssue].self, forKey: .other)) ?? []
        trackNames = (try? c.decode([ProofIssue].self, forKey: .trackNames)) ?? []
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
    - trackNames: the writer always puts song titles in single quotes, like 'blinding lights'. Ignore lines \
      that start with "favs:" or "least favs:" (those are plain lists of titles, unquoted on purpose). List any \
      song title mentioned in the body that is NOT wrapped in quotes. Only flag text that is clearly being \
      used as a song title, not ordinary words.

    Respect intentional style: deliberate lowercase, slang, album/artist stylizations, fragments used for \
    effect, and profanity are not errors. When unsure, leave it out.

    Reply with ONLY this JSON, no other text:
    {"summary": "one short sentence on overall mechanics",
     "typos": [{"text": "exact word or short phrase from the review", "suggestion": "correct spelling", "note": "short reason"}],
     "punctuation": [{"text": "exact short snippet", "note": "what's wrong"}],
     "runOns": [{"text": "first few words of the sentence", "note": "where it could break"}],
     "commas": [{"text": "exact short snippet", "note": "what's wrong"}],
     "other": [{"text": "exact short snippet", "note": "what's wrong"}],
     "trackNames": [{"text": "the song title as written", "note": "short reason"}]}
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

extension ProofStats {
    /// Track titles that appear in the review without quotes around them.
    /// The review without "favs:" / "least favs:" lines (those are plain lists of song titles,
    /// written without quotes on purpose).
    static func withoutFavLines(_ review: String) -> String {
        review.components(separatedBy: .newlines)
            .filter { $0.range(of: #"^\s*(least\s+)?fav(s|ou?rites?)?\s*:"#, options: [.regularExpression, .caseInsensitive]) == nil }
            .joined(separator: "\n")
    }

    static func unquotedTracks(in review: String, tracks: [String]) -> [ProofIssue] {
        let quotes = Set("'\"‘’“”`")
        let text = review as NSString
        var out: [ProofIssue] = []
        var seen = Set<String>()
        for raw in tracks {
            let title = raw
                .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)   // (feat. …)
                .replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)               // - Remastered
                .trimmingCharacters(in: .whitespaces)
            guard title.count >= 3, seen.insert(title.lowercased()).inserted else { continue }
            let singleWord = !title.contains(" ")
            var searchRange = NSRange(location: 0, length: text.length)
            while true {
                let r = text.range(of: title, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                if r.location == NSNotFound { break }
                searchRange = NSRange(location: r.location + r.length, length: text.length - r.location - r.length)
                let before = r.location > 0 ? Character(text.substring(with: NSRange(location: r.location - 1, length: 1))) : nil
                let after = r.location + r.length < text.length ? Character(text.substring(with: NSRange(location: r.location + r.length, length: 1))) : nil
                // whole words only
                if let b = before, b.isLetter || b.isNumber { continue }
                if let a = after, a.isLetter || a.isNumber { continue }
                let quoted = (before.map { quotes.contains($0) } ?? false) || (after.map { quotes.contains($0) } ?? false)
                if !quoted {
                    out.append(ProofIssue(text: text.substring(with: r), suggestion: "'\(text.substring(with: r))'",
                                          note: singleWord ? "Track name without quotes (if you meant the song)." : "Track name without quotes."))
                    break
                }
            }
        }
        return out
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
