# AOTYbox

A native iPhone app for [Album of the Year](https://www.albumoftheyear.org) (AOTY), written in SwiftUI with iOS 26 Liquid Glass.

There is no server in between. The app reads AOTY directly on your phone through a hidden web view that uses **your own signed-in AOTY session**. Ratings, reviews, likes, follows and listens you make in the app land on your real AOTY account, exactly as if you'd used the website.

> Unofficial. Not affiliated with or endorsed by Album of the Year.

---

## Contents

- [Install](#install)
- [Features](#features)
  - [Releases](#releases)
  - [Charts](#charts)
  - [Search](#search)
  - [Album page](#album-page)
  - [Your rating & review box](#your-rating--review-box)
  - [Reviews, likes & swipes](#reviews-likes--swipes)
  - [Share cards](#share-cards)
  - [Artist pages](#artist-pages)
  - [Profiles](#profiles)
  - [Notifications](#notifications)
  - [Now Playing](#now-playing)
  - [Learn (Genius + Ask AI)](#learn-genius--ask-ai)
  - [Notes (proofreading)](#notes-proofreading)
  - [Share sheet (AOTYbox)](#share-sheet-aotybox)
  - [Settings](#settings)
  - [Look & feel](#look--feel)
- [How it works](#how-it-works)
- [Privacy](#privacy)
- [Building](#building)
- [CI & releases](#ci--releases)
- [Project layout](#project-layout)
- [Troubleshooting](#troubleshooting)

---

## Install

Builds are unsigned IPAs made by GitHub Actions on every push to `main`.

**LiveContainer / AltStore / SideStore source (recommended):**

```
https://raw.githubusercontent.com/BoxIsMyNamee/aotybox/source/source.json
```

**Direct IPA (always the newest build):**

```
https://raw.githubusercontent.com/BoxIsMyNamee/aotybox/source/AOTYClient.ipa
```

Both are mirrored to `raw.githubusercontent.com`, because GitHub's release download links often time out (HTTP 504). Each build is also attached to a GitHub release (`build-N`); the 10 newest are kept.

- **Requires:** iOS 26.
- **SideStore / AltStore:** the app includes a share extension, so it signs **two app IDs**, the app and `…aotyclient.share`.
- **First launch:** a **Welcome** sheet opens AOTY's real login page.
  - If AOTY's Cloudflare "Verify you are human" check appears first, it's handled in that same sheet, with a plain explanation.
  - Once you're logged in, the header says **Signed in as …** and **Done** starts the app. **Skip** lets you browse signed out.
  - Updating from an older version you were already signed in on skips this.
  - Everything personal needs that session: your box on album pages, likes, follows, notifications, your profile.
  - You can sign in again any time from **Settings → Account**.

---

## Features

### Releases

- **This Week** and **New**, switched with a floating glass control at the bottom. You can tap a segment or drag across it. Upcoming lives on the Search tab.
- **Albums / Singles toggle:** the round button beside the switcher. Releases always opens on Albums.
- Each row shows:
  - the cover, artist and title
  - the release date and type ("Nov 6 • LP")
  - genres (filled in in the background)
  - **critic and user scores**, as a number, a colored bar and a label
  - a green ★ for AOTY's *Must Hear* albums
- Both feeds stay loaded, so switching between them is instant. Pull down to refresh.
- **Notification bell** at the top right (see [Notifications](#notifications)).
- The **AOTY wordmark** sits at the top left.

### Charts

- **Critics** and **Users** highest-rated charts, switched at the bottom.
- A year picker covers the last 15 years plus **All time**. The title reads "Best of 2026" or "All Time".
- Rows show rank, cover, scores, release date, and genres on their own line.

### Search

- **Stays in the app.** Results are native, not the AOTY website:
  - **Artists:** a horizontal row of round artist photos.
  - **Albums:** full rows with critic and user scores.
- **Suggestions as you type:** these come from AOTY's own search-box lookup (`/search-autocomplete.php`), the same one the website uses. They start after the third letter, like on the site.
  - Albums show their cover with "artist · year".
  - Artists show their photo.
  - Tapping a suggestion opens it straight away.
  - Matching recent searches appear first. **Search for "…"** at the bottom runs a full search.
- AOTY's empty duplicate artists with the same name (no photo, no releases) are hidden when a real one exists.
- **Recent searches:** you can remove one at a time, or use **Clear**.
- **Upcoming:** a grid of AOTY's next 24 releases, with the release date under each in your accent color. It replaced "New This Week".
- **Now Playing card** at the top (see [Now Playing](#now-playing)).
- Tapping the Search tab again resets it.

### Album page

Top to bottom:

1. **Header:**
   - a large cover: tap to view it full screen; **hold** it to open an AI chat about the album
   - the title, and the artist name, which you can tap to open the artist page
   - the date, type and label
   - critic and user scores with counts
   - the year ranking ("#47 of 2020"), and genres
2. **Learn & Listen:** one card, two rows.
   - **Learn about this Album** opens the Genius write-up, tracklist and Ask AI.
   - **Listen on Marvis Pro / Apple Music** uses whichever app you picked in Settings.
3. **Your box:** your score, review, and Listen / Like / Save. See [below](#your-rating--review-box).
4. **Tracklist:** track numbers, titles, lengths, and **AOTY track scores colored like album scores**. Tap a track to Learn about that song. If AOTY has no tracklist, it falls back to Apple Music or Genius.
5. **Popular User Reviews:** see [Reviews](#reviews-likes--swipes). **See all user reviews** opens the full list, with:
   - a rating distribution you can tap to filter by score range
   - sorting at the bottom
6. **Critic Reviews.**
7. **Similar albums.**

The share and compass buttons at the top share the album, or open it on AOTY.

### Your rating & review box

A rounded card on every album page when you're signed in, built like AOTY's own box:

- your picture and name in your **donor color**
- **If you've rated it:** your score in large rounded numbers, with a colored bar.
- **If not:** a `0–100` field and a **Rate** button. The keyboard also gets **Rate** and **Done** buttons.
- **Your review**, shown large and in full:
  - If AOTY cut it off with "… read more", the app fetches the whole review from your review page.
  - **Show more / Show less** on very long reviews.
- **Add a review** box with **Post**, which turns green once you've typed 3 characters, matching AOTY's minimum.
- **Drafts are kept:** what you type is saved per album as you go. It survives leaving the page, switching tabs and closing the app. If you left while editing, the album reopens in edit mode with your changes. A draft is cleared on **Post**, **Save** or **Cancel**.
- **Proof** (yellow, on the left while writing or editing) copies your draft into **Notes** and jumps there.
  - It fills Notes' **Album** field with the artist and title, and turns the tracklist check on.
  - Old proof results are cleared so you can proofread straight away. Your draft stays in the box.
- **Edit → Save / Cancel** on an existing review:
  - Your score and full text become editable.
  - It never edits AOTY's cut-off copy, so a long review can't get chopped.
  - **Save** sends only what changed.
- **Listened / Like / Save** along the bottom. Tap to toggle; the icon fills in your accent color.
- All of it uses AOTY's own requests:
  - `insertRatingLarge.php`, `insertReview.php`
  - the site's Update action for edits, read from AOTY's own code each time
  - `insertListened.php` / `deleteListened.php`
  - `insertAlbumLike.php` / `deleteAlbumLike.php`
  - `addSpinList.php` / `removeSpinList.php`
- If AOTY rejects something, the change is undone and AOTY's reply is shown. Your typed text is kept.
- **Hold the card** to share your review as an image (see [Share cards](#share-cards)).

### Reviews, likes & swipes

Every user review row shows:

- the avatar and name in the reviewer's **donor color**; tap to open their profile
- how long ago it was posted
- their score
- the review text, where **links are tappable**
- **Read full review**
- a 💬 comment button (opens the review page) and a ♥ heart with the like count

**Likes:**

- Tap the heart to like or unlike.
- Tap the **number** to see **who liked it**: AOTY's "Liked By" list, with pictures, names in color and "Follows you" tags. Tap someone to open their profile.
- On **your own** reviews, the heart opens the Liked By list, since you can't like your own.
- If AOTY refuses a like, a toast says why, e.g. *"AOTY's hourly like limit reached."*

**Apollo-style swipes:**

- The row slides over a colored strip.
- It lights up with a tick when you pass the trigger point, then glides back when you let go.
- **Swipe left** on a review: **Like** / **Unlike** (pink). This also works on your own reviews, where it does nothing.
- **Swipe right:**
  - **View** on other people's reviews (opens the review)
  - **Learn** on yours (opens the album's Learn page)
- On albums and songs elsewhere: **right = Learn** (green), **left = Open** in your music app (blue).

### Share cards

**Hold any review** (your box, reviews on profiles, reviews on album pages) to see it as a card, then tap **Share as Image**. The card has:

- a blurred cover backdrop
- the cover, album title, artist and score with its colored bar, all centered
- the **whole** review: cut-off reviews are fetched in full, and long ones get a smaller font
- the reviewer's avatar and name in their color, plus the AOTY wordmark

It's rendered at 3× and shared through the iOS share sheet: Messages, Instagram, Save Image, and so on.

- Only the **image** is shared, with no caption text tagging along into Messages.
- In the hold-down pop-up, long reviews show **from the top** (cover first) and fade out at the bottom. The shared image always has the whole review.
- The hold-down menu also has **Open in Safari** (the review's page on AOTY) and **Copy Link**.

### Artist pages

- A hero photo with the artist name over it.
- **Critic** and **user** score boxes, with review and rating counts.
- **Followers**, with a **Follow / Following** button that uses AOTY's `followArtist.php` / `unfollowArtist.php`. The count updates right away.
- **Details:**
  - born, country, members, member of, also known as
  - genres, and a website link
- **Discography** switcher at the bottom: **Albums · EPs · Singles · Features** (Features = AOTY's "Appears On").
  - Each row shows **both critic and user scores** and the Must Hear star.
  - Newest releases come first.
- **Filters** button, which opens a sheet:
  - Tick extra release types to add to the Albums tab, then tap ✓ to apply.
  - The list is **AOTY's own type list for that artist**: Mixtape, Compilation, Live, DJ Mix, Remix, Soundtrack, Instrumental, Reissue, Demo, Miscellaneous, Music Video, Video, Unofficial…
  - **All / None** select everything or nothing.
  - Your picks are remembered.

### Profiles

- **Your profile** is in the Profile tab. Other people's open from any username.
- The header shows:
  - the avatar: tap for full size
  - your display name, large and in your **donor color**, with the `(handle)` under it
  - stats on one small line ("520 ratings · 100 followers…")
  - your bio, with tappable links
- **Custom background:** pick any photo in **Settings → Profile Background**. It shows behind the top of your profile and fades into the page. It's stored only on your phone.
- **Reviews:**
  - Each one shows a large cover (tap the artist name for the artist page, anywhere else for the album).
  - Album titles wrap onto up to 3 lines.
  - Each has a big score badge.
  - **Show more** fetches the full text.
  - Hearts, comments, swipes and share cards work as on album pages.
  - **View All Reviews** opens the paged list.
- **Recently Rated**, with "You" score chips. **View All Ratings** is paged.
- **Friends:** avatars with their name colors.
- The gear icon is Settings; the ••• menu has more.

### Notifications

- The **bell** on Releases checks every 3 minutes for AOTY's unread marker. That's the small teal `.alertNotification` dot the website shows next to your avatar.
- When something is unread, the bell gets a **red badge**.
- Checking never opens your notifications page, so it can't mark anything as read.
- Tap the bell for a **native list**:
  - the avatar, a **bold** name, what happened ("commented on your review of …"), and how long ago
  - unread items are highlighted, with a dot
- Tap a notification to open what it's about.
- Swipe the sheet down to close it.
  - **↻** reloads the list.
  - The compass icon opens the full page on AOTY.
- Opening the list marks notifications read, same as on the website.

### Now Playing

- Shown at the top of Search: what's playing in Apple Music or Marvis (through iOS's system music player). It needs Apple Music access once.
- **Equalizer bars** move up and down while music plays, and rest when it's paused.
- **Album** finds the release on AOTY and opens it.
- **Learn** opens the song's Learn page.

### Learn (Genius + Ask AI)

**Songs:** **Lyrics · About · Comments · Ask AI**, in a floating glass switcher at the bottom. It hides while you type.

- **Lyrics:** from Genius, with annotations you can tap and images inline.
- **About:** the Genius description.
- **Comments:** Genius comments.
- **Ask AI:** chat about the song.
  - Suggested questions to start, like "What is this song about?" and "What's the story behind this album?"
  - "Meaning" answers come in a fixed format: **TL;DR / The Meaning / Production & Sound / Noteworthy Lyrics / Key Contributors**.
  - It shows a "thinking" bubble while it works.

**Albums:** **About · Tracks · Ask AI**. Tap a track to open its song page.

**AI providers:**

- **Google Gemini:** free key; answers can use Google Search.
- **Anthropic Claude:** can use web search.
- **Any OpenAI-compatible API:** OpenAI, OpenRouter, Groq, or a local server.

Your key is stored in the iPhone **Keychain** and sent only to the provider you chose.

### Notes (proofreading)

A scratchpad for reviews you write elsewhere. It **never rewrites your text**.

- **Paste | Proof | Copy** buttons. **Proof** is green.
- **Repeated words** are counted on your phone.
- **Proof**, using your AI provider, flags:
  - typos
  - punctuation
  - run-on sentences
  - comma problems
  - **track names that aren't in quotes**
- **Optional album field** (turn it on in Settings). When you name an album, it checks every track you mention against the real tracklist.
- Lines starting with **favs:** or **least favs:** (or favorites: / least favorites:) are ignored by the track-name check. Those are plain lists of titles, unquoted on purpose.
- Text can arrive from your review box (**Proof** button) or from other apps through the [share sheet](#share-sheet-aotybox).
- Your text and album are remembered between launches.

### Share sheet (AOTYbox)

A share extension called **AOTYbox** appears in the iOS share sheet. If you don't see it, tap **More** at the end of the app row and turn it on.

- **Text** (a Google Keep note, Notes, anything) opens the app on **Notes** with that text in the box.
  - From Keep: open a note, then **⋮ → Send → Send via other apps → AOTYbox**.
  - It replaces what was in Notes.
- **Music links** open that **album in AOTY**:
  - Marvis, Apple Music, song.link / album.link, Spotify, Tidal, YouTube Music and Deezer.
  - It works for songs and albums, whether the link is shared on its own or inside a sentence.
  - Apple Music links are identified with Apple's iTunes lookup. Other services go through [Odesli](https://odesli.co) (the service behind song.link) to find the matching Apple Music album.
  - The app then searches AOTY for that artist and album and opens the album page on the Search tab. If there's no exact match, you get AOTY's search results.
- The text goes in as base64, so emoji, quotes, "&" and line breaks survive.
- If iOS ever refuses to open the app from the extension, the text is copied and you're told to tap **Paste** in Notes.
- The same thing works through links: `aotybox://notes?text=…` (or `?b64=…`), and `aotybox://open?b64=<base64 music link>`.

### Settings

- **Accent Color:** tints everything, including the launch animation.
- **Appearance:** System, Light, **Black** (pure black, for OLED) or **Dim** (softer grays).
- **Profile Background:** choose, change or remove the image.
- **Notes:** the album track-name check on or off.
- **Account:** sign in, or sign out on this device.
- **Music App:** Marvis Pro or Apple Music, and how songs are opened (song link, album link with track, or song ID).
- **AI Assistant:** provider, key, model (Gemini models are found automatically) and web search.
- **Cache:** see its size and clear it.
- **Diagnostics:**
  - page checks
  - a **capture** tool that copies the relevant AOTY page code (nothing private) when something needs fixing

### Look & feel

- **iOS 26 Liquid Glass:**
  - the tab bar, glass buttons and floating glass switchers
  - a glass round filter button on artist pages, and a glass Singles toggle on Releases
- **Launch animation:** stacked cards in your accent color fly in, then the logo pops.
- **App icon:** the white AOTY wordmark on near-black.
- **Haptics:** on swipes, toggles, likes, ratings and errors.
- **Scores are only ever AOTY's real 0–100 values.** The app never guesses one; if a score can't be read, none is shown.
- **Name colors** (donor colors) are the same everywhere: reviews, profiles, friends, Liked By and share cards.
- Covers and avatars are cached in memory and on disk, and preloaded, so they don't pop in.

---

## How it works

- **No backend.** `AOTYScraper` owns one hidden `WKWebView`, logged in with your AOTY cookies.
  - Pages are fetched **from inside that web view** (same origin), so requests look exactly like the website's own.
  - When AOTY fills a page in after it loads (artist discographies, for example), the app loads the page for real and waits for it.
  - If Cloudflare challenges a request, a sheet lets you pass the check yourself.
- **Parsing:** `Scripts/extract.js` turns AOTY's HTML into JSON. Its main pieces:
  - `aotyAlbumBlocks` reads album cards.
  - `aotyAlbum`, `aotyArtist` and `aotyProfile` read album, artist and profile pages.
  - `aotyUserReview` and `aotyMyAlbumBox` read review rows and your box.
  - `aotyNotifications` and `aotyNotificationList` read the header dot and the notifications page.
  - the artist search reader also returns names and photos.

  Scores come from AOTY's own number and bar width, and anything outside 0–100 is dropped. The same script runs in Node for the tests.
- **Actions** go through `AOTYAPI.albumAction` and friends. They are form POSTs to AOTY's own `/scripts/*.php` endpoints (with `X-Requested-With: XMLHttpRequest`, as the site sends). Endpoints that might change, like the review Update action, are read from AOTY's own JavaScript each time.
- **Cloudflare:** only one check sheet is ever shown at a time. It used to pop up and away for every blocked screen.
  - The sheet closes on its own once the page loads past the check.
  - Screens that failed while you were blocked reload automatically.
  - On first run, the Welcome sign-in sheet takes care of the check instead.
- **Requests** are serialized and throttled, and background work (genre lookups, for example) waits behind what you're looking at.
- **Cache:** pages are kept on disk for **15 minutes**, keyed by a hash of the parser.
  - A new parser version never reuses old results.
  - Empty album lists are never stored.
  - Pull-to-refresh skips the cache.
- **Genius** lyrics and descriptions are read through a separate `genius.js` script.

---

## Privacy

- Your AOTY login stays in the app's web view cookie store on your phone.
- AI keys are in the Keychain. Your text goes only to the provider you pick, and only when you use Ask AI or Proof.
- The profile background image and notes are stored only on your phone.
- No analytics, no tracking, no servers of ours.

---

## Building

Requirements: **Xcode 26**, iOS 26 SDK, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen            # generates AOTYClient.xcodeproj from project.yml
open AOTYClient.xcodeproj
```

- Swift 5 language mode; deployment target **iOS 26.0**.
- Bundle ID `com.harper.aotyclient`; URL scheme `aotybox://` (e.g. `aotybox://learn?artist=…&title=…&album=…`).
- `Scripts/extract.js`, `Scripts/genius.js` and `Art/aoty-logo@3x.png` are bundled as resources.
- To sideload your own build, set your Team under Signing, or build unsigned as CI does:
  `xcodebuild -scheme AOTYClient -sdk iphoneos CODE_SIGNING_ALLOWED=NO`

**Parser tests** (Node 22):

```bash
npm install --no-save linkedom@0.18
node tests/extract.test.mjs
```

There are two kinds:

- **Synthetic tests:** made from real AOTY markup captured in the app. They cover signed-in album blocks, your box, notifications, artist types, follow buttons, the Liked By list and search.
- **Archive tests:** run against archived AOTY pages when the Wayback Machine is reachable.

---

## CI & releases

| Workflow | What it does |
| --- | --- |
| **Build unsigned IPA** (`build-ipa.yml`) | Builds on `macos-15` with the newest Xcode 26 and packages `AOTYClient.ipa`. Writes `source.json` (AltStore/LiveContainer format, with the app icon) and publishes release `build-N`, keeping the newest 10. Mirrors the IPA and `source.json` to the `source` branch for fast `raw.githubusercontent.com` downloads. |
| **Launch test** (`smoke.yml`) | Installs the build on a simulator, launches it, and screenshots every tab to the `ci-screens` branch. |
| **Test extractors** (`test-extract.yml`) | Runs the parser tests whenever `Scripts/` or `tests/` change. |

The version is `0.1.<run number>`.

---

## Project layout

```
AOTYClient/
  AOTYClientApp.swift        app, tabs, launch splash, Settings, appearance
  AI/                        AI client (Gemini / Claude / OpenAI-compatible) + settings
  Models/Models.swift        AlbumBlock, AlbumDetail, UserReview, Profile, MyAlbumBox, …
  Networking/
    AOTYScraper.swift        hidden WKWebView, queue, throttle, cache, Cloudflare handling
    AOTYAPI.swift            every AOTY read + action (rate, review, like, follow, search, …)
    GeniusClient.swift       Genius search, lyrics, annotations
    GenreStore.swift         background genre / release-date lookups
  Scripts/extract.js         AOTY HTML → JSON
  Scripts/genius.js          Genius HTML → JSON
  Networking/MusicLinkResolver.swift   Apple Music / song.link / Spotify link → artist + album
AOTYShare/ShareViewController.swift    the "AOTYbox" share extension
  Views/
    ReleasesView.swift       Releases, notification bell + list, glass helpers, AOTY logo
    ChartsView.swift         Charts
    SearchView.swift         Search, suggestions, in-app results, Upcoming
    AlbumDetailView.swift    Album page
    MyAlbumCard.swift        Your rating / review / Listen-Like-Save box
    ArtistView.swift         Artist page, follow, discography filters
    ProfileView.swift        Profiles, reviews, ratings, friends
    UserReviewsView.swift    All user reviews + distribution
    Components.swift         album rows, score views, user review rows
    Hearts.swift             likes, Liked By sheet, like toast
    SwipeRow.swift           Apollo-style swipes
    ShareCard.swift          review share cards
    ProfileBackground.swift  custom profile background
    NowPlaying.swift         Now Playing card + equalizer bars
    SongView.swift           Learn (song) + Ask AI chat
    LearnAlbumView.swift     Learn (album)
    ProofView.swift          Notes / proofreading
    GlassSegmented.swift     floating glass switcher
    DiagnosticsView.swift    checks + capture tool
tests/extract.test.mjs       parser tests
project.yml                  XcodeGen spec
```

---

## Troubleshooting

- **LiveContainer says "HTTP 504" or 0 KB:** GitHub's release links are timing out. Use the `raw.githubusercontent.com` source above.
- **Nothing personal shows up:** sign in under **Settings → Account**.
- **A "verify you are human" sheet appears:** AOTY's Cloudflare check. Tap the box. The sheet closes by itself once you're through, and the app reloads what it was showing.
- **AOTYbox isn't in the share sheet:** tap **More** at the end of the app row in the share sheet and turn it on. With SideStore, make sure both app IDs were registered.
- **A shared music link opens search results instead of the album:** AOTY didn't have an exact match for that title, so pick it from the results.
- **A like un-does itself:** you've probably hit AOTY's hourly like limit, and the toast will say so. Wait a bit.
- **Something looks wrong on a page:** **Settings → Diagnostics → Capture**, then share the copied text in an issue. It contains AOTY page code only, never your password.
