# Aftermath: iptv-org stream browser

## Goal
Replace the two manually entered stream URLs (EST/PST) with a browser over the public
iptv-org playlist. Users search and filter streams, favorite them, and play a favorite
from the ornament. Remove explicit Toonami references; "Aftermath" remains the app name.

## Decisions (from brainstorming)
- Source: `https://iptv-org.github.io/iptv/index.m3u`, fetched at runtime. Nothing is bundled.
- Browse model: search plus category and country filters over the full index.
- Manual URL entry is removed. iptv-org is the only source.
- Unchanged: 4:3 window, uniform resizing, volume slider, ornament auto-hide, tap to play/pause.

## Components
Each lives in its own file under `aftermath/`.

- **`IPTVStream`** (struct, Codable, Identifiable, Hashable; named to avoid `Foundation.Stream`):
  `id` (the URL string, because iptv-org lists several feeds per tvg-id), `name`, `url`,
  `channelID` (tvg-id, optional), `categories` (group-title split on `;`), `country` (suffix of
  tvg-id, optional), `logoURL` (optional).
- **`PlaylistParser`**: pure `parse(_ m3u: String) -> [Stream]`. Reads `#EXTINF` attributes
  (`tvg-id`, `tvg-logo`, `group-title`) and the display name after the final comma, then pairs
  each with the next URL line. It skips entries with no valid URL and ignores unknown directives
  such as `#EXTVLCOPT`. It never throws on malformed input.
- **`StreamCatalog`** (`@Observable`): `state` (idle, loading, loaded, failed), `streams`,
  `query`, `category`, `country`, and a computed `filtered` list (case-insensitive name match,
  exact category and country match). It fetches the index and writes the raw text to the caches
  directory. If the fetch fails, it loads the cached copy when one exists. Otherwise it enters
  `failed` and the UI offers a retry.
- **`FavoritesStore`** (`@Observable`): an ordered `[Stream]` stored as JSON in `UserDefaults`.
  It offers `toggle(_:)` and `contains(_:)`. Favorites keep the full entry so they still play if
  the stream later leaves the index.
- **`StreamBrowserView`**: a sheet that replaces `SettingsView`. It has a search field,
  category and country menus, and a lazy list of rows (logo or initials, name, category, star
  toggle). Tapping a row selects the stream and dismisses the sheet.
- **`ContentView`**: `Channel` and the `estURL`/`pstURL` storage are removed. The ornament
  shows one button per favorite (logo or initials, highlighted when playing) and a browse
  button in place of the gear. `switchChannel` becomes `play(_ stream: Stream)`, with the same
  `AVPlayerItem` replacement and volume handling.

## Error handling
- Playback failure: observe the current item's `status`. On `.failed`, show a "Stream
  unavailable" overlay on the video. There is no pre-validation of streams.
- Catalog failure: a failed state with a retry in the browser sheet. A cached copy is used when present.
- No favorites yet: the ornament shows only the browse button, and the empty video area prompts "Browse streams".

## Migration and cleanup
- Drop the old `estURL` and `pstURL` `@AppStorage` keys without migrating them.
- README: remove the Toonami line, the EST/PST feature and usage text, and the "must find your own
  m3u8 links" note. Describe browsing iptv-org, favorites, and iptv-org's disclaimer that it hosts
  no video and only links to publicly available streams. Link to iptv-org/iptv.
- Remove the stale `WebFetch(domain:api.toonamiaftermath.com)` entry from `.claude/settings.local.json`.
- Keep the app name, bundle name and project files named "aftermath".

## Testing
- Unit tests (new test target) for `PlaylistParser` using fixture snippets: normal entries, missing
  attributes, a missing URL, extra `#EXTVLCOPT` lines, and Windows line endings. Also tests for
  `StreamCatalog.filtered` and `FavoritesStore` toggle and persistence.
- Manual check in the visionOS simulator: load the index, search and filter, favorite, play,
  relaunch to confirm favorites persist, and play a known-dead stream to see the overlay.

## Out of scope
EPG and program guide, iCloud sync of favorites, stream health checks, logo caching beyond
`AsyncImage` defaults, and any bundled or hardcoded stream list.

## Open risks
- App Store review treats IPTV-style apps case by case. The app hosts nothing and loads a public
  third-party playlist, but this is not legal advice.
- The index is large, around 10k entries. Parse off the main thread and use a lazy list.
