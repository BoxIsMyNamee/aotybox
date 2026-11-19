# AOTYbox: handoff for AI assistants

Read this before touching the code. `README.md` is the user-facing feature guide; this file is
how the app works, how to ship changes, and how the owner likes to work.

## What it is

A native SwiftUI iOS 26 client for **albumoftheyear.org (AOTY)**: browse releases and charts,
open albums/artists/profiles, and rate, review, like, follow and list albums with the user's
real AOTY account. AOTY has **no public API**, so everything is read from AOTY's own HTML,
on the phone, through a hidden `WKWebView` that holds the user's AOTY session.

There are also some extras: Learn (Genius lyrics and notes plus Ask AI), Proof (an AI proofreader
for reviews), Identify a Song (mic → Shazam fingerprint), share cards, a share extension and
Lock Screen widgets.

- Owner: Harper (GitHub `BoxIsMyNamee`), one personal user, sideloaded with **SideStore**
  (free Apple account; no paid developer program).
- Bundle ID `com.harper.aotyclient`; URL scheme `aotybox://`.
- Deployment target iOS 26.0, Swift 5 language mode, iPhone only, portrait.

## Ship loop (there is no local Xcode)

1. Edit the Swift and JS files, then commit and push to `main`.
2. GitHub Actions `build-ipa.yml` (macos-15, newest Xcode 26) runs `xcodegen`, builds an
   **unsigned** Release IPA, publishes GitHub release `build-N`, and mirrors `AOTYClient.ipa` and
   `source.json` to the **`source` branch**.
3. The owner installs from the raw link:
   `https://raw.githubusercontent.com/BoxIsMyNamee/aotybox/source/AOTYClient.ipa`
   (raw links, because release-asset downloads 504'd / showed 0 KB in sideloaders).
4. Other workflows: `smoke.yml` (boots the simulator and checks the app launches without
   crashing) and `test-extract.yml` (runs `node tests/extract.test.mjs` against the
   extractors with linkedom).

Notes:
- The Xcode project is **generated** from `project.yml`; never commit `*.xcodeproj`. Add new
  targets, Info.plist keys (`INFOPLIST_KEY_…`) and resources in `project.yml`.
- To check CI, poll the REST API (GraphQL `gh run/release list` may be blocked):
  `gh api "repos/BoxIsMyNamee/aotybox/actions/runs?head_sha=$SHA"`, then
  `gh api repos/BoxIsMyNamee/aotybox/actions/jobs/$JOB/logs | grep error:`.
- macOS runners sometimes sit queued and get cancelled. Rerun with
  `gh api -X POST repos/BoxIsMyNamee/aotybox/actions/runs/$ID/rerun`.
- Common compile failures: "unable to type-check this expression in reasonable time" (split
  long arithmetic or view expressions into typed lets or helpers), and Accelerate/vDSP overloads
  (use explicit `outputReal:/outputImaginary:` inout forms).
- Nothing can be tested on a device from CI. Say clearly what is built but unverified.

## Targets

| Target | Path | Purpose |
|---|---|---|
| AOTYClient | `AOTYClient/` + `Shared/` | the app |
| AOTYShare | `AOTYShare/` | Share-sheet extension: music links → `aotybox://open?b64=…` (opens that album); other text → `aotybox://notes?b64=…`. Opens the host app by calling `openURL:options:completionHandler:` up the responder chain (APPLICATION_EXTENSION_API_ONLY = YES). |
| AOTYWidget | `AOTYWidget/` + `Shared/` | Lock Screen `accessoryCircular` widget ("Identify a Song", `widgetURL aotybox://listen`) + a `ControlWidget` button running `ListenIntent` (openAppWhenRun). |

`Shared/ListenIntent.swift` is compiled into both the app and the widget. `ListenRequest` hands
off through a NotificationCenter post plus a `listenPending` UserDefaults flag (for cold launch).
Each extension uses one of the free account's few App IDs; avoid adding more extensions casually.

## Architecture

### Networking (`AOTYClient/Networking/`)
- **`AOTYScraper.swift`** (`@MainActor` singleton), the core:
  - Uses a hidden 2×2 `WKWebView` that is kept in the window hierarchy so WebKit doesn't throttle it.
  - It sits on a same-origin page (`/robots.txt`) and runs `fetch()` from JS, so AOTY's cookies
    and Cloudflare clearance come along.
  - The parser `Scripts/extract.js` (~46 KB) is loaded **once per page** (`ensureExtractor`,
    reset on `didCommit`), not re-sent with every call.
  - Requests are **serialized** (one at a time) with a 0.4 s gap. This is deliberate: bursts
    trigger Cloudflare. Don't parallelize.
  - `fetch(path, kind:as:)` runs the page through `aotyExtract(kind, html, url)` and decodes the
    JSON result.
  - Cache: 15-minute TTL in memory and on disk (`Caches/aoty-v2`), with keys prefixed by a hash
    of `extract.js` so a parser change invalidates old entries. On a network error it falls back
    to a stale copy. `forget(path)` and `bypassCache()` exist for pull-to-refresh and after actions.
  - Fallbacks: if a `fetch()` hits a challenge, it loads the page for real; if that also fails,
    it shows the Challenge sheet (only one at a time). While the sheet is up the scraper is
    `paused`; `challengeFinished()` resumes, clears the cache and posts `.aotyReady`.
  - `postExtract` sends AOTY's own form POSTs (ratings, likes and so on).
  - `runJS` / `runOnRealPage` run JS for one-offs and diagnostics.
  - Full page loads in the hidden view block images, media and fonts (WKContentRuleList).
- **`AOTYAPI.swift`** (actor): typed calls such as `album`, `artist`, `profile`, `userReviews`,
  `me`, `notifications`, `suggestions` (`/search-autocomplete.php`), `findAlbumSlug`,
  `findArtistPath`, `reviewLikers`, `setReviewLike`, `setArtistFollow`, `albumAction`,
  `updateReview`, `fullReview` and so on.
  - Actions call AOTY's own `/scripts/*.php` endpoints, the same ones the site's buttons use:
    insertRatingLarge, insertReview, updateReview (its endpoint and parameters are read from
    `albumScript.js` at runtime), insert/deleteListened, insert/deleteAlbumLike,
    add/removeSpinList, insert/deleteReviewLike, showUserReviewLikes, followArtist/unfollowArtist.
- **`Scripts/extract.js`**: every parser (`aotyExtract` kinds: blocks, chart, album, userReviews,
  me, profile, follows, userReviewList, textBlocks, artist, artistSearch, notifications).
  - Albums in lists are read from `.image a[href*='/album/']`. When signed in, the "…" menu link
    is `href="#"`, which broke the selectors once.
  - Artist type filters come from the page's `?type=` links. Multi-word slugs use `+`
    (`dj+mix`); skip `&s=`/`filter=` links and the all/featured links.
  - Tests live in `tests/extract.test.mjs`.
- **`GenreStore`**: genres and release dates for rows on Releases. It fetches album pages in the
  background, only for visible rows, only when the queue is idle, and saves the results permanently.
- **`SongRecognizer.swift`**:
  - A Swift port of **SongRec/shazamio's** Shazam signature: 16 kHz mono, 2048-point Hann FFT
    every 128 samples, peak spreading and recognition, binary signature plus CRC32.
  - Sends it to `amp.shazam.com/discovery/v5/...`; no ShazamKit entitlement is needed, so it
    works sideloaded.
  - `MicRecorder` uses AVAudioEngine → 16 kHz Int16, with a `.playAndRecord` + `.mixWithOthers`
    session.
  - The logic was checked step by step against shazamio's Python reference.
- **`MusicLinkResolver`**: Apple Music links via the iTunes lookup API; any other service via
  Odesli (`api.song.link`).
- **Genius** (`Genius.swift`, `GeniusClient.swift`, `Scripts/genius.js`): lyrics, annotations,
  about text, comments and album info.

### AI (`AOTYClient/AI/`)
- `AIClient`: Gemini (default; model auto-resolves through the available flash models and
  retries on 503/429), Anthropic, or OpenAI-compatible.
- Keys are kept in the iPhone **Keychain** and sent only to the chosen provider. Never log keys
  or ask the user to paste them into chat.
- The owner's Gemini key is on paid Tier 1 (prepaid balance, with Google AI Pro Developer
  Program credits applied first).

### Views (`AOTYClient/Views/`), key pieces
- Tabs: Releases, Charts, Search, Profile, Notes (Proof). Each tab is an `AppStack`
  (NavigationPath) with an `@Environment(\.push)` action. Routes are in `Navigation.swift`
  (AlbumRoute, SongRoute, ArtistRoute, LearnAlbumRoute, UserRoute and so on).
- **Releases**: This Week / New feeds (Upcoming lives in Search), with a floating
  `GlassSegmented` switcher and an Albums/Singles toggle. The header has a glass pill containing
  the mic (`ListenButton`) and the bell (`NotificationBell`).
  - The bell shows only a red dot (no number). It polls the `me` page every 3 minutes, only while
    the app is in the foreground.
  - **Never fetch `/notifications/` automatically: opening it marks everything read on AOTY.**
- **AlbumDetailView / MyAlbumCard**: the user's rating, review, listened, like and list controls.
  - Post becomes Edit, which then becomes Save.
  - Drafts are saved under `draft.<id>` / `draft.edit.<id>`.
  - A truncated review loads the full text before editing.
  - The yellow Proof button sends the review to Notes.
- **SongView / LearnAlbumView** (Learn): Lyrics / About / Comments / Ask AI tabs.
  - **Song Learn always opens on Lyrics.**
  - Ask AI state lives in `ChatThread` (`@Observable`, owned by the page). It keeps running across
    tab switches and is saved per song/album in Application Support/AIChats.
  - Bubbles have "Ask again" and edit (pencil) buttons.
  - Optional Settings toggle: "Ask right away on Learn" (default off).
  - Tapping the song header opens the AOTY album.
- **ProofView** (Notes tab): AI proofreading.
  - Optionally matches an album (iTunes first, then AOTY search) to check that track names are in
    quotes. Lines starting with `favs:` / `least favs:` are ignored.
  - Hard 60-second limit, with a Stop button.
- **SwipeRow**: an Apollo-style full-swipe. Album/song rows and review rows read their actions
  from Settings → Swipe Actions (`SwipeSettings.swift`). Defaults: albums right = Learn,
  left = Open in Music App; reviews right = Learn/View, left = Like.
- **Images.swift**: `ImageCache`. Raw bytes go to a 500 MB URLCache and are decoded **at display
  size** (ImageIO thumbnails in 128/256/512/1024 buckets). `Cover` / `Avatar` pass
  `maxPixel = size × 3`. `warm()` only downloads; the full-size image is used only for the cover
  viewer and share cards.
- Other features: ShareCard (review → image card, shared as the image only), ProfileBackground
  (custom banner), Hearts (likes, likers sheet), ArtistView (follow, type filters sheet),
  DiagnosticsView (captures for debugging parsers).
- Theme: default accent is green `#34C759`. Settings also has: Theme (Black/Dim), color-blind
  scores, Swipe Actions, Notes, Account, Music App (Apple Music/Marvis), AI, Cache, Diagnostics.

### URL scheme
`aotybox://open?b64=<music url>`, `aotybox://notes?text=|b64=`,
`aotybox://learn?artist=&title=[&album=]`, `aotybox://listen`.

## Owner's preferences (important)

- **Scores are only AOTY's real 0–100 values.** Never compute or invent scores.
- Minimal bloat: the owner removes features they consider bloat (e.g. a "People You Follow"
  rating toggle was reverted). When unsure, keep it small, put it behind an off-by-default
  setting, or ask.
- iOS 26 Liquid Glass look: floating glass bottom switchers, glass pills. Donor name colors stay
  consistent.
- Avoid UI that pops in. Pages gather their data, then show it all at once.
- Feedback arrives as screenshots and screen recordings; make focused changes, then ship a build.
- Replies should be short and clear: what changed, the build number, the raw IPA link, and
  honestly what is unverified on device.
- Never complete CAPTCHAs/Cloudflare checks for the user. Never enter payment details. Treat the
  owner's email and API keys as private.

## Gotchas learned the hard way

- `withAnimation` from UIKit pan callbacks gets dropped; SwipeRow uses an implicit
  `.animation(dragging ? nil : .smooth, value: offset)` and guards against `onEnd` firing twice.
- Cloudflare: the hidden view uses a Safari-like `applicationNameForUserAgent`. The first-run
  sign-in sheet starts at the AOTY home page and pauses the scraper; loading challenge pages in
  parallel made the check spin forever.
- Use task-group timeouts carefully: a group waits for its children, so a stuck request can hang
  it. `AOTYScraper.withTimeout` and Proof's `within()` race with a continuation instead.
- `ImageRenderer` share cards render at scale 3; the context-menu preview is capped at 600 pt
  and top-aligned for long text.
- Free SideStore accounts: App ID limit (app + share + widget = 3 today).
