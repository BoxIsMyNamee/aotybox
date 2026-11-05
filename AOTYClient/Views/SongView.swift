import SwiftUI

/// Song page: Genius bio, lyrics with tappable annotations, comments, and an AI chat.
/// Falls back to the chat when Genius has nothing for the song.
struct SongView: View {
    let artist: String
    let title: String
    let album: String?
    let albumCover: URL?

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
    @State private var chat: [ChatMessage] = []
    @Environment(\.openURL) private var openURL

    private var nothingOnGenius: Bool { !loading && hit == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if loading && tab != .ask {
                    ProgressView("Looking up on Genius…").frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    switch tab {
                    case .lyrics: lyricsView
                    case .about: aboutView
                    case .comments: commentsView
                    case .ask: SongChatView(context: aiContext, messages: $chat, nothingOnGenius: nothingOnGenius)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = song?.url ?? hit?.url {
                Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .accessibilityLabel("Open on Genius")
            }
        }
        .sheet(item: $selectedRef) { ref in AnnotationSheet(referent: ref).presentationDetents([.medium, .large]).accentTint() }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Cover(url: song?.art ?? hit?.art ?? albumCover, size: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(song?.title ?? title).font(.title3.bold()).lineLimit(2)
                Text(song?.artist ?? artist).font(.subheadline).foregroundStyle(.secondary)
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
                Text(about).font(.body).textSelection(.enabled)
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
                            Text(c.body).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
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

    private func load() async {
        guard hit == nil, loading else { return }
        let found = await GeniusClient.search(artist: artist, title: title)
        hit = found
        guard let found else {
            loading = false
            tab = .ask
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
        let empty = (lyrics?.segments.isEmpty ?? true) && song?.about == nil
        if empty { tab = .ask }
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
                            Text(a.body).font(.body).textSelection(.enabled)
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

struct SongChatView: View {
    let context: String
    @Binding var messages: [ChatMessage]
    let nothingOnGenius: Bool
    @State private var input = ""
    @State private var thinking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private let suggestions = ["What is this song about?", "Explain the hardest lines", "How was it received?", "Any samples or interpolations?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !AISettings.isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connect an AI to ask about this song", systemImage: "sparkles").font(.headline)
                    Text("Add a Gemini, Claude, or OpenAI-compatible API key in Settings → AI Assistant. Gemini has a free tier.")
                        .font(.callout).foregroundStyle(.secondary)
                    NavigationLink("Open AI settings") { AISettingsView() }
                }
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else {
                if nothingOnGenius && messages.isEmpty {
                    Text("Genius doesn't have this one. Ask anything about the song, its lyrics, or what people have said about it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(messages) { m in bubble(m) }
                if thinking {
                    HStack(spacing: 8) { ProgressView(); Text(AISettings.provider.searchesWeb ? "Thinking and searching…" : "Thinking…").foregroundStyle(.secondary) }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if messages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { input = s; Task { await send() } }
                                    .buttonStyle(.bordered).font(.callout)
                            }
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask about this song…", text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { Task { await send() } }
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
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
        }
        .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }

    private func send() async {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        input = ""; error = nil
        messages.append(ChatMessage(role: .user, text: q))
        thinking = true; defer { thinking = false }
        let system = """
        You are a music expert inside an Album of the Year app. Answer questions about one song: its meaning, \
        lyrics, references, production, samples, reception, and online discussion. Be concise and specific; \
        quote at most a line or two of lyrics. If you search the web, prefer reputable music sources. \
        If you're unsure, say so.

        \(context)
        """
        do {
            messages.append(try await AIClient.reply(system: system, history: messages))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
