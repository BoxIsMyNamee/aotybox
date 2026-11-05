# AOTYClient

A native SwiftUI client for albumoftheyear.org, built on the unofficial community API
([edideaur/AOTY-api](https://github.com/edideaur/AOTY-api), hosted at `https://aoty.prigoana.com`).
Requires iOS 17 or later.

## What's in v0.1

- **Releases:** This Week / New / Upcoming, with infinite scroll.
- **Charts:** critic or user highest-rated, by year or all-time.
- **Search:** albums (it runs when you press Search, not on every keystroke).
- **Album page:** cover, critic and user scores, ranking, genres, streaming links, tracklist with track ratings, critic reviews, popular user reviews, and similar albums.
- **Settings:** the API base URL (so you can switch to your own instance) and a button to clear the cache.

## Run it

**Option A: XcodeGen (recommended)**
```bash
brew install xcodegen
cd AOTYClient
xcodegen
open AOTYClient.xcodeproj
```
Then pick your Team under Signing & Capabilities and run.

**Option B: New Xcode project**
1. File → New → Project → iOS App (SwiftUI). Name it `AOTYClient`.
2. Delete the generated `ContentView.swift` and `AOTYClientApp.swift`.
3. Drag the `AOTYClient/` folder from this zip into the project, with "Create groups" selected.
4. **Xcode 26:** go to Build Settings and set **Default Actor Isolation** to `nonisolated`, or set the Swift Language Version to 5. The new-project default is MainActor isolation, which breaks decoding inside the networking actor.

## How the app treats the API

The default host is one person's free Cloudflare Worker, so the client is built to be gentle with it:
- **Serialized requests:** requests go out one at a time, at least 250 ms apart.
- **Cache:** responses are kept on disk and reused for 15 minutes.
- **Attribution:** every request sends an attributing User-Agent.
- **Lighter album loads:** `/album` is called with `minimal=true`, which skips the worker's extra stats and credits requests.

## Files

```
AOTYClient/
  AOTYClientApp.swift        tabs + Settings
  Networking/AOTYAPI.swift   actor client: throttle, cache, errors
  Models/Models.swift        Decodable types mirroring the API's src/types.ts
  Views/                     Releases, Charts, Search, AlbumDetail, shared components
```

## Next endpoints worth wiring

`/artist?slug=`, `/album/user-reviews`, `/album/distribution` (for a rating histogram),
`/on-this-day`, `/must-hear`, `/discover/anticipated`, `/user?username=` (read-only profile),
and `/batch` (up to 10 paths in one request). Full list: `https://aoty.prigoana.com/openapi.json`.
