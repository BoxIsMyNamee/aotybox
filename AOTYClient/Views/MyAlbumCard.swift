import SwiftUI
import UIKit

/// Your box on an album page. Rated/reviewed: your score with its bar and your review.
/// Not yet: a score field with Rate, and an "Add a review" box with Post. Listen / Like / Save on top.
/// Everything uses AOTY's own button requests with your signed-in session.
struct MyAlbumCard: View {
    @State var box: MyAlbumBox
    let slug: String?
    @AppStorage("profileUsername") private var myUsername = ""
    @State private var scoreText = ""
    @State private var reviewText = ""
    @State private var busy: String?          // which action is running
    @State private var error: String?
    @State private var expanded = false
    @State private var editing = false
    @FocusState private var focus: Field?
    private enum Field { case score, review }

    private var id: String { box.albumID.map(String.init) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Avatar(url: box.avatar.flatMap(URL.init(string:)), name: box.name ?? myUsername, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    Text(box.name ?? myUsername).font(.headline).lineLimit(1)
                        .foregroundStyle(box.nameColor.map { Color(hex: $0) } ?? .primary)
                    scoreArea
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                actionButton("Listen", on: "Listened", icon: "headphones", flag: box.listened ?? false,
                             add: "insertListened.php", remove: "deleteListened.php") { box.listened = $0 }
                actionButton("Like", on: "Liked", icon: "heart", flag: box.liked ?? false,
                             add: "insertAlbumLike.php", remove: "deleteAlbumLike.php") { box.liked = $0 }
                actionButton("Save", on: "Saved", icon: "plus", flag: box.saved ?? false,
                             add: "addSpinList.php", remove: "removeSpinList.php") { box.saved = $0 }
            }
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))

            if let review = box.review, !review.isEmpty, !editing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(linkified(review)).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 6)
                    HStack {
                        if review.count > 280 {
                            Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                                .font(.caption.weight(.semibold)).buttonStyle(.borderless)
                        }
                        Spacer(minLength: 0)
                        Button {
                            reviewText = review
                            scoreText = box.rating.map { String(Int($0.rounded())) } ?? ""
                            error = nil
                            withAnimation(.snappy) { editing = true }
                            focus = .review
                        } label: {
                            Text("Edit").bold().frame(width: 76, height: 34)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if editing || (box.canReview ?? true) {
                reviewComposer
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focus == .score {
                    Button("Rate") { Task { await rate() } }.bold()
                        .disabled(Int(scoreText).map { !(0...100).contains($0) } ?? true)
                }
                Button("Done") { focus = nil }
            }
        }
    }

    // MARK: Score

    @ViewBuilder private var scoreArea: some View {
        if let r = box.rating, !editing {
            HStack(spacing: 8) {
                Text(String(Int(r.rounded())))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(scoreColor(r)).frame(width: 44 * r / 100)
                }
                .frame(width: 44, height: 4)
            }
        } else {
            HStack(spacing: 8) {
                TextField("0–100", text: $scoreText)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .score)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 64, height: 32)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                Button { Task { await rate() } } label: {
                    Group {
                        if busy == "rate" { ProgressView().controlSize(.mini) } else { Text("Rate") }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 54, height: 32)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(busy != nil || Int(scoreText).map { !(0...100).contains($0) } ?? true)
            }
        }
    }

    private func rate() async {
        guard let v = Int(scoreText), (0...100).contains(v) else { error = "Score must be 0–100."; return }
        focus = nil; error = nil; busy = "rate"
        defer { busy = nil }
        if await AOTYAPI.shared.albumAction("insertRatingLarge.php", ["albumID": id, "value": String(v)]) != nil {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { box.rating = Double(v) }
            forgetPage()
        } else {
            error = "AOTY didn't accept the rating. Try again, or use Rate or review on AOTY."
        }
    }

    // MARK: Review

    private var reviewComposer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reviewText)
                    .focused($focus, equals: .review)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if reviewText.isEmpty {
                    Text("Add a review").font(.callout).foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 180)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                if !reviewText.isEmpty && reviewText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                    Text("At least 3 characters").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            if editing {
                Button("Cancel") { focus = nil; error = nil; withAnimation(.snappy) { editing = false } }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).padding(.trailing, 6)
            }
            Button { Task { if editing { await saveEdit() } else { await post() } } } label: {
                Group {
                    if busy == "post" { ProgressView().controlSize(.small).tint(.white) } else { Text(editing ? "Save" : "Post").bold() }
                }
                .frame(width: 76, height: 34)
                .background(reviewText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 ? Color.accentColor : Color.gray.opacity(0.4),
                            in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(busy != nil || reviewText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
        }
    }

    private func post() async {
        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        focus = nil; error = nil; busy = "post"
        defer { busy = nil }
        let reply = await AOTYAPI.shared.albumAction("insertReview.php", ["albumID": id, "text": text])
        if let reply, !reply.contains("type=\"password\"") {   // a login form back means the session lapsed
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation { box.review = text; reviewText = "" }
            forgetPage()
        } else {
            let said = reply.map { $0.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(120) } ?? ""
            error = "AOTY didn't accept the review" + (said.isEmpty ? "." : ": \(said)") + " Your text is still here."
        }
    }

    /// Edit mode's Save: re-rate if the score changed, then update the review text.
    private func saveEdit() async {
        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        focus = nil; error = nil; busy = "post"
        defer { busy = nil }
        if let v = Int(scoreText), (0...100).contains(v), Double(v) != box.rating {
            guard await AOTYAPI.shared.albumAction("insertRatingLarge.php", ["albumID": id, "value": String(v)]) != nil else {
                error = "AOTY didn't accept the new score. Your text is still here."; return
            }
            box.rating = Double(v)
        }
        if text != box.review {
            guard await AOTYAPI.shared.updateReview(albumID: id, text: text) else {
                error = "AOTY didn't accept the edit. Your text is still here — try again, or use Rate or review on AOTY."; return
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { box.review = text; reviewText = ""; editing = false }
        forgetPage()
    }

    // MARK: Listen / Like / Save

    private func actionButton(_ title: String, on: String, icon: String, flag: Bool,
                              add: String, remove: String, set: @escaping (Bool) -> Void) -> some View {
        Button {
            Task {
                let new = !flag
                set(new)                                   // optimistic
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if await AOTYAPI.shared.albumAction(new ? add : remove, ["albumID": id]) == nil {
                    set(flag)
                    error = "Couldn't update \(title.lowercased()). Try again."
                } else { forgetPage() }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: flag ? (icon == "plus" ? "checkmark" : icon == "heart" ? "heart.fill" : icon) : icon)
                    .font(.title3)
                    .foregroundStyle(flag ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 24)
                Text((flag ? on : title).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flag ? on : title)
    }

    /// So the next visit shows the change instead of a saved copy.
    private func forgetPage() {
        if let slug { Task { await AOTYScraper.shared.forget("/album/\(slug).php") } }
    }
}
