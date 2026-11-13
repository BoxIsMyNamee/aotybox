import SwiftUI
import CryptoKit
import UIKit

/// Song page: Genius bio, lyrics with tappable annotations, comments, and an AI chat.
/// Falls back to the chat when Genius has nothing for the song.
struct SongView: View {
    let artist: String
    let title: String
    let album: String?
    let albumCover: URL?
    var artistPath: String? = nil
    @Environment(\.push) private var pushArtist

    enum Tab: String, CaseIterable, Identifiable {
        case lyrics = "Lyrics", about = "About", comments = "Comments", ask = "Ask AI"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .lyrics
    @State private var hit: GeniusClient.SongHit?
    @State private var song: GeniusClient.Song?
    @State private var lyrics: GeniusClient.Lyrics?
    @State private var referents: [Int: GeniusClient.Referent] = [:]
    @State private var comments: [GeniusClient.Comment] = []
    @State private var loading = true
    @State private var lyricsError: String?
    @State private var selectedRef: GeniusClient.Referent?
    @State private var chat = ChatThread()
    @Environment(\.openURL) private var openURL
    @State private var keyboardUp = false

    private var nothingOnGenius: Bool { !loading && hit == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if loading && tab != .ask {
                    ProgressView("Looking up on Genius…").frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    switch tab {
                    case .lyrics: lyricsView
                    case .about: aboutView
                    case .comments: commentsView
                    case .ask: SongChatView(context: aiContext, thread: chat, nothingOnGenius: nothingOnGenius)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        // Section switcher floats at the bottom like the other pages; it steps aside while typing.
        .safeAreaInset(edge: .bottom) {
            if !keyboardUp {
                GlassSegmented(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = song?.url ?? hit?.url {
                Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .accessibilityLabel("Open on Genius")
            }
        }
        .sheet(item: $selectedRef) { ref in AnnotationSheet(referent: ref).presentationDetents([.medium, .large]).accentTint() }
        .onAppear { chat.attach(ChatThread.key("song", artist, title)) }
        .task { await load() }
        // Ask right away on Learn: don't wait forever on Genius, and start the moment Ask AI is opened.
        .task { try? await Task.sleep(for: .seconds(4)); kickOffAsk() }
        .onChange(of: tab) { if tab == .ask { kickOffAsk() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Cover(url: song?.art ?? hit?.art ?? albumCover, size: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(song?.title ?? title).font(.title3.bold()).lineLimit(2)
                Button { pushArtist(ArtistRoute(path: artistPath ?? "", name: artist)) } label: {
                    Text(song?.artist ?? artist).font(.subheadline).foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                if let a = song?.album ?? album { Text(a).font(.caption).foregroundStyle(.tertiary) }
                if let d = song?.releaseDate { Text(d).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer()
        }
    }

    // MARK: Lyrics

    @ViewBuilder private var lyricsView: some View {
        if let lyrics, !lyrics.segments.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(stanzas(lyrics.segments).enumerated()), id: \.offset) { _, stanza in
                    Text(attributed(stanza))
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                if !referents.isEmpty {
                    Text("Tap a highlighted line to read its annotation.").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "genius-ref", let id = Int(url.host ?? ""), let ref = referents[id] {
                    selectedRef = ref
                    return .handled
                }
                return .systemAction
            })
        } else if lyrics?.instrumental == true {
            Text("This song is an instrumental.").foregroundStyle(.secondary)
        } else if hit != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(lyricsError ?? "No lyrics on Genius yet.").foregroundStyle(.secondary)
                if let u = hit?.url { Button("Open on Genius") { openURL(u) } }
                Button("Ask AI about this song") { tab = .ask }
            }
        } else {
            noGenius
        }
    }

    /// Split segments into stanzas at blank lines, keeping annotation ids.
    private func stanzas(_ segs: [GeniusClient.Segment]) -> [[GeniusClient.Segment]] {
        var out: [[GeniusClient.Segment]] = [[]]
        for seg in segs {
            let parts = seg.t.components(separatedBy: "\n\n")
            for (i, p) in parts.enumerated() {
                if i > 0 { out.append([]) }
                let trimmed = (out[out.count - 1].isEmpty) ? p.replacingOccurrences(of: #"^\n+"#, with: "", options: .regularExpression) : p
                if !trimmed.isEmpty { out[out.count - 1].append(.init(t: trimmed, r: seg.r)) }
            }
        }
        return out.filter { !$0.isEmpty && !$0.allSatisfy { $0.t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    private func attributed(_ segs: [GeniusClient.Segment]) -> AttributedString {
        var result = AttributedString()
        for seg in segs {
            var piece = AttributedString(seg.t.trimmingCharacters(in: .init(charactersIn: "\n")) == seg.t ? seg.t : seg.t)
            if let r = seg.r, referents[r] != nil {
                piece.link = URL(string: "genius-ref://\(r)")
                piece.backgroundColor = Color.secondary.opacity(0.22)
                piece.foregroundColor = .primary
            }
            result += piece
        }
        // Section labels like [Chorus] in bold.
        if let range = result.range(of: #"^\[[^\]]+\]"#, options: .regularExpression) {
            result[range].font = .body.bold()
            result[range].foregroundColor = .secondary
        }
        return result
    }

    // MARK: About

    @ViewBuilder private var aboutView: some View {
        if let about = song?.about {
            VStack(alignment: .leading, spacing: 12) {
                GeniusRichText(text: about)
                HStack(spacing: 16) {
                    if let n = song?.annotationCount { Label("\(n) annotations", systemImage: "text.quote") }
                    if let v = song?.pageviews { Label("\(v.formatted(.number.notation(.compactName))) views", systemImage: "eye") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        } else if hit != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Genius has no bio for this song yet.").foregroundStyle(.secondary)
                Button("Ask AI about this song") { tab = .ask }
            }
        } else {
            noGenius
        }
    }

    // MARK: Comments

    @ViewBuilder private var commentsView: some View {
        if !comments.isEmpty {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(comments) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(url: c.avatar, name: c.author, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.author).font(.subheadline.weight(.semibold))
                                if let d = c.date { Text(d, style: .relative).font(.caption2).foregroundStyle(.tertiary) }
                                Spacer()
                                if c.votes != 0 { Label("\(c.votes)", systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(linkified(c.body)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Divider()
                }
            }
        } else if hit != nil {
            Text("No comments on Genius yet.").foregroundStyle(.secondary)
        } else {
            noGenius
        }
    }

    private var noGenius: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn't find this song on Genius.").foregroundStyle(.secondary)
            Button("Ask AI about it instead") { tab = .ask }
        }
    }

    // MARK: Loading

    private func kickOffAsk() {
        SongChatView(context: aiContext, thread: chat, nothingOnGenius: nothingOnGenius).autoAsk()
    }

    private func load() async {
        guard hit == nil, loading else { return }
        let found = await GeniusClient.search(artist: artist, title: title)
        hit = found
        guard let found else {
            loading = false
            kickOffAsk()
            return
        }
        async let songTask = try? GeniusClient.song(id: found.id)
        async let refsTask = GeniusClient.referents(songId: found.id)
        async let commentsTask = GeniusClient.comments(songId: found.id)
        do { lyrics = try await GeniusClient.lyrics(url: found.url) }
        catch { lyricsError = "Couldn't load lyrics from Genius." }
        song = await songTask
        referents = await refsTask
        comments = await commentsTask
        loading = false
        kickOffAsk()
    }

    // MARK: AI context

    private var aiContext: String {
        var parts: [String] = []
        parts.append("Song: \"\(song?.title ?? title)\" by \(song?.artist ?? artist).")
        if let a = song?.album ?? album { parts.append("Album: \(a).") }
        if let d = song?.releaseDate { parts.append("Released: \(d).") }
        if let about = song?.about { parts.append("Genius bio:\n\(about.prefix(3000))") }
        if let l = lyrics?.plainText, !l.isEmpty { parts.append("Lyrics (from Genius):\n\(l.prefix(8000))") }
        let notes = referents.values.prefix(12).compactMap { r -> String? in
            guard let a = r.annotations.first else { return nil }
            return "• \"\(r.fragment.prefix(120))\": \(a.body.prefix(400))"
        }
        if !notes.isEmpty { parts.append("Some Genius annotations:\n" + notes.joined(separator: "\n")) }
        if hit == nil { parts.append("Genius has no page for this song, so rely on your knowledge and web search.") }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Annotation sheet

struct AnnotationSheet: View {
    let referent: GeniusClient.Referent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(referent.fragment)
                        .font(.callout.italic())
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    ForEach(referent.annotations) { a in
                        VStack(alignment: .leading, spacing: 8) {
                            GeniusRichText(text: a.body)
                            HStack(spacing: 10) {
                                if a.verified { Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.tint) }
                                if !a.authors.isEmpty { Text(a.authors.prefix(3).joined(separator: ", ")) }
                                Spacer()
                                Label("\(a.votes)", systemImage: "arrow.up")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        if a != referent.annotations.last { Divider() }
                    }
                }
                .padding()
            }
            .navigationTitle("Genius Annotation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - AI chat

/// One Ask AI conversation. Owned by the page, not the chat view, so a question keeps
/// running (and its answer lands) while you look at another tab.
@Observable final class ChatThread {
    var messages: [ChatMessage] = [] { didSet { save() } }
    var thinking = false
    var thinkingSince: Date?
    var error: String?
    var input = ""
    @ObservationIgnored private var key: String?

    /// Ties this chat to one song or album, loading the conversation saved for it last time.
    /// Saved answers are reused, so going back to a song doesn't ask the AI again.
    func attach(_ key: String) {
        guard self.key == nil else { return }
        self.key = key
        if messages.isEmpty, let data = try? Data(contentsOf: Self.file(key)),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    private func save() {
        guard let key else { return }
        let url = Self.file(key)
        if messages.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(messages).write(to: url, options: .atomic)
    }

    static func key(_ kind: String, _ artist: String, _ title: String) -> String {
        "\(kind)|\(artist)|\(title)".lowercased()
    }

    private static func file(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return URL.applicationSupportDirectory.appending(path: "AIChats/\(name).json")
    }
}

struct SongChatView: View {
    let context: String
    let thread: ChatThread
    let nothingOnGenius: Bool
    var subject: String = "song"
    private var messages: [ChatMessage] { thread.messages }
    private var thinking: Bool { thread.thinking }
    @FocusState private var focused: Bool
    @State private var showAISettings = false

    private var suggestions: [String] {
        subject == "song"
            ? [meaningQuestion, "Explain the hardest lines", "How was it received?", "Any samples or interpolations?"]
            : [meaningQuestion, "How was it received?", "Standout tracks?", "Themes and influences", "Who produced it?"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !AISettings.isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connect an AI to ask about this \(subject)", systemImage: "sparkles").font(.headline)
                    Text("Add a Gemini, Claude, or OpenAI-compatible API key in Settings → AI Assistant. Gemini has a free tier.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open AI settings") { showAISettings = true }
                        .sheet(isPresented: $showAISettings) { NavigationStack { AISettingsView() }.accentTint() }
                }
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else {
                if nothingOnGenius && messages.isEmpty {
                    Text("Genius doesn't have this one. Ask anything about the song, its lyrics, or what people have said about it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(messages) { m in bubble(m) }
                if thinking, let started = thread.thinkingSince { ThinkingBubble(since: started) }
                if let error = thread.error {
                    HStack(alignment: .firstTextBaseline) {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Spacer()
                        Button { retry() } label: { Label("Retry", systemImage: "arrow.clockwise") }
                            .font(.footnote).buttonStyle(.borderless)
                    }
                }
                if messages.isEmpty {
                    ChipLayout(spacing: 8) {
                        ForEach(suggestions.prefix(3), id: \.self) { s in
                            Button(s) { thread.input = s; ask() }
                                .buttonStyle(.bordered).font(.callout)
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask about this \(subject)…", text: Bindable(thread).input, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { ask() }
                    Button { ask() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(thread.input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                }
                Text("Answers come from \(AISettings.provider.name) and may be wrong.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 6) {
            Text(LocalizedStringKey(m.text))
                .textSelection(.enabled)
                .padding(10)
                .background(m.role == .user ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: RoundedRectangle(cornerRadius: 12))
            if !m.sources.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(m.sources.prefix(5), id: \.url) { s in
                        Link(destination: s.url) { Label(s.title, systemImage: "link").font(.caption).lineLimit(1) }
                    }
                }
            }
            if !thinking {
                if m.role == .user {
                    Button { edit(m) } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Edit question")
                        .font(.footnote).foregroundStyle(.secondary).buttonStyle(.borderless)
                } else if m.id == messages.last?.id {
                    Button { retry() } label: { Label("Ask again", systemImage: "arrow.clockwise") }
                        .font(.footnote).foregroundStyle(.secondary).buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }

    /// Drops the last answer (or failed attempt) and asks the same question again.
    private func retry() {
        guard !thinking, let i = messages.lastIndex(where: { $0.role == .user }) else { return }
        let q = messages[i].text
        thread.messages.removeSubrange(i...)
        thread.error = nil
        thread.input = q
        ask()
    }

    /// Puts a question back in the box to change; it and everything after it are removed.
    private func edit(_ m: ChatMessage) {
        guard !thinking, let i = messages.firstIndex(where: { $0.id == m.id }) else { return }
        thread.messages.removeSubrange(i...)
        thread.error = nil
        thread.input = m.text
        focused = true
    }

    /// The original first suggestion; tapping it gets the structured answer.
    private var meaningQuestion: String {
        subject == "song" ? "What is this song about?" : "What's the story behind this \(subject)?"
    }

    /// The structured answer for the "meaning" question.
    private var meaningFormat: String {
        let lyricsScope = subject == "song" ? "this song" : "across this \(subject)"
        return """

        For this answer use EXACTLY this structure. Put each label in bold on its own line, then its content:
        **TL;DR:** 1–2 sentences on the core meaning or story.
        **The Meaning**
        1–3 short paragraphs: context, backstory and analysis grounded in the lyrics, the artist's own interviews \
        and statements, and reputable coverage. Make clear what the artist has said versus what is interpretation.
        **Production & Sound**
        A few brief notes: genre, notable samples or interpolations, production techniques.
        **Noteworthy Lyrics**
        1–4 short lines from \(lyricsScope), each on its own line in quotes. Don't explain them unless a line is obscure.
        **Key Contributors**
        • Writer(s): names
        • Producer(s): names
        • Noteworthy: famous or unexpected contributors (leave this line out if there are none)

        Rules: quote no more than 4 lyric lines in total, and only in Noteworthy Lyrics. If a credit can't be \
        verified, write "Unconfirmed" instead of guessing. No other sections and no closing summary.
        """
    }

    /// The Settings → AI "Ask right away on Learn" kick-off: the meaning question, sent in the background.
    @MainActor func autoAsk() {
        guard UserDefaults.standard.bool(forKey: AISettings.autoAskKey), AISettings.isConfigured,
              thread.messages.isEmpty, !thread.thinking else { return }
        thread.input = meaningQuestion
        let thread = thread, system = systemPrompt(structured: true)
        Task { @MainActor in await Self.send(thread, system: system) }
    }

    /// Sends in a task that isn't tied to this view, and drops the keyboard so the tab bar comes back.
    private func ask() {
        focused = false
        let thread = thread, system = systemPrompt(structured: thread.input.trimmingCharacters(in: .whitespacesAndNewlines) == meaningQuestion)
        Task { @MainActor in await Self.send(thread, system: system) }
    }

    private func systemPrompt(structured: Bool) -> String {
        """
        You are a music expert inside an Album of the Year app. Answer questions about one \(subject): its meaning, \
        lyrics, references, production, samples, reception, and online discussion. Be concise and specific; \
        quote at most a line or two of lyrics. If you search the web, prefer reputable music sources. \
        If you're unsure, say so.
        \(structured ? meaningFormat : "")

        \(context)
        """
    }

    @MainActor private static func send(_ thread: ChatThread, system: String) async {
        let q = thread.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thread.thinking else { return }
        thread.input = ""; thread.error = nil
        thread.messages.append(ChatMessage(role: .user, text: q))
        thread.thinking = true; thread.thinkingSince = Date()
        defer { thread.thinking = false; thread.thinkingSince = nil }
        do {
            thread.messages.append(try await AIClient.reply(system: system, history: thread.messages))
        } catch {
            thread.error = error.localizedDescription
        }
    }
}


// MARK: - Genius text with inline images

/// Genius plain-text bodies put images on their own line as a bare URL. Show those as pictures
/// (tap to view full screen) and everything else as text.
struct GeniusRichText: View {
    let text: String
    @State private var viewing: Viewing?
    private struct Viewing: Identifiable { let id: URL }

    private enum Piece: Hashable { case text(String), image(URL) }

    private static func isImage(_ line: String) -> URL? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("http"), !t.contains(" "), let u = URL(string: t) else { return nil }
        let host = u.host ?? "", path = u.path.lowercased()
        let imageHost = host.contains("images.genius.com") || host.contains("images.rapgenius.com")
            || host.contains("gstatic.com") || host.contains("googleusercontent.com") || host.contains("i.imgur.com")
            || host.contains("pbs.twimg.com") || host.contains("media.giphy.com")
        let imageExt = [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains { path.hasSuffix($0) }
        return (imageHost || imageExt) ? u : nil
    }

    private var pieces: [Piece] {
        var out: [Piece] = []
        var buffer: [String] = []
        func flush() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.text(joined)) }
            buffer = []
        }
        for line in text.components(separatedBy: "\n") {
            if let u = Self.isImage(line) { flush(); out.append(.image(u)) } else { buffer.append(line) }
        }
        flush()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(pieces, id: \.self) { piece in
                switch piece {
                case .text(let t):
                    Text(linkified(t)).font(.body).textSelection(.enabled)
                case .image(let u):
                    CachedImage(url: u, contentMode: .fit) {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)).frame(height: 180)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { viewing = Viewing(id: u) }
                }
            }
        }
        .fullScreenCover(item: $viewing) { CoverViewer(url: $0.id, title: "").accentTint() }
    }
}


/// "The AI is working" bubble: animated dots, what it's doing, and how long it's been.
struct ThinkingBubble: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: since, by: 0.35)) { ctx in
            let t = ctx.date.timeIntervalSince(since)
            let phase = Int(t / 0.35) % 3
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle().frame(width: 7, height: 7)
                            .opacity(i == phase ? 1 : 0.3)
                            .scaleEffect(i == phase ? 1.15 : 0.9)
                    }
                }
                .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status(t)).font(.callout.weight(.medium))
                    Text("\(Int(t))s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.25), value: phase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Thinking")
    }

    private func status(_ t: TimeInterval) -> String {
        let web = AISettings.provider.searchesWeb
        switch t {
        case ..<2: return "Thinking…"
        case ..<8: return web ? "Searching the web…" : "Thinking…"
        case ..<20: return "Writing an answer…"
        default: return "Still working — long answers take a bit…"
        }
    }
}
