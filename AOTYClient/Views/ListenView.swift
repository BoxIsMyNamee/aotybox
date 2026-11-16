import SwiftUI
import AVFoundation

/// Mic button for the Releases header: hears what's playing and opens that song in Learn.
struct ListenButton: View {
    @Environment(\.push) private var push
    @State private var showing = false
    @State private var found: SongRecognizer.Match?

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "waveform.and.mic")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Identify a song")
        // From the Lock Screen widget or control (possibly before this screen existed).
        .onAppear { if ListenRequest.take() { showing = true } }
        .onReceive(NotificationCenter.default.publisher(for: ListenRequest.note)) { _ in
            if ListenRequest.take() { showing = true }
        }
        .sheet(isPresented: $showing, onDismiss: {
            if let m = found {
                found = nil
                push(SongRoute(artist: m.artist, title: m.title, album: m.album, cover: m.cover))
            }
        }) {
            ListenSheet { m in found = m; showing = false }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .accentTint()
        }
    }
}

struct ListenSheet: View {
    let onMatch: (SongRecognizer.Match) -> Void

    enum Phase: Equatable { case listening, noMatch, denied, failed(String) }
    @State private var phase: Phase = .listening
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            switch phase {
            case .listening:
                ListeningWaves().frame(height: 60)
                Text("Listening…").font(.title3.weight(.semibold))
                Text("Hold your phone near the music.").font(.callout).foregroundStyle(.secondary)
            case .noMatch:
                Image(systemName: "questionmark.circle").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Couldn't find a match").font(.title3.weight(.semibold))
                Button("Try again") { attempt += 1 }.buttonStyle(.borderedProminent)
            case .denied:
                Image(systemName: "mic.slash").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Microphone access is off").font(.title3.weight(.semibold))
                Button("Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(.borderedProminent)
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.secondary)
                Text(msg).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Try again") { attempt += 1 }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .task(id: attempt) { await listen() }
    }

    /// Records up to ~13 seconds, asking Shazam at 4, 8 and 13 seconds; stops at the first match.
    private func listen() async {
        phase = .listening
        guard await AVAudioApplication.requestRecordPermission() else { phase = .denied; return }
        let mic = MicRecorder()
        do { try mic.start() } catch { phase = .failed("Couldn't start the microphone."); return }
        defer { mic.stop() }
        var lastError: String?
        for wait in [4.0, 4.0, 5.0] {
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            let samples = mic.collected.suffix(16000 * 12)
            do {
                if let m = try await Task.detached(priority: .userInitiated, operation: { try await SongRecognizer.identify(samples) }).value {
                    onMatch(m)
                    return
                }
                lastError = nil
            } catch {
                lastError = "Couldn't reach Shazam. Check your connection."
            }
        }
        phase = lastError.map(Phase.failed) ?? .noMatch
    }
}

/// Bars that rise and fall while listening.
private struct ListeningWaves: View {
    static func height(t: Double, i: Int) -> CGFloat {
        let d = Double(i)
        let a: Double = sin(t * (4 + d * 0.7) + d * 1.3)
        let b: Double = sin(t * 2.3 + d * 2.1)
        let wave: Double = (a + b) / 2
        return CGFloat(12 + 44 * (wave + 1) / 2)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<9, id: \.self) { i in
                    Capsule().fill(.tint)
                        .frame(width: 6, height: Self.height(t: t, i: i))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
