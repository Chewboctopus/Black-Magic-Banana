# Changelog

All notable changes to Black Magic Banana are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.5.0] – 2026-04-03

### Added
- **Gallery Browser window** — "Browse ↗" button on each gallery column opens a
  dedicated full-size resizable window showing a **5×4 thumbnail grid** (20 items
  per page) with filter combo, ◀ Prev / Next ▶ paging, and a full action bar:
  Use as Ref, Load Settings, Open, **Reveal in Finder**, Add to Pool, Delete, Close.
- **Double-click to ref**: double-clicking a thumbnail in the browser immediately
  loads the item into the first available ref slot.
- **Reveal in Finder** added both in the gallery browser window and as a dedicated
  inline-gallery button (`Reveal in Finder`) on both ImageGen and MovieGen tabs.
- On close, the browser syncs its selection back to the inline gallery in the main panel.

### Fixed
- **Broken simulated scroll** — the unreliable `ScrollBar`/`Slider` widget (which
  could not receive trackpad events in Fusion's UIManager) has been replaced with
  reliable **▲ / ▼ step buttons** that are correctly enabled/disabled based on
  current scroll position.

### Security
- **macOS Keychain integration** – The Gemini API key is now stored in the
  macOS login Keychain via the `security` command-line tool instead of being
  written to the plaintext `cleanroom_settings.conf` file.
- **Automatic migration** – On first launch after upgrading, any API key
  already present in the conf file is silently moved to Keychain and removed
  from the file. No manual action required.
- On non-macOS platforms (or if the `security` tool is unavailable) the
  script falls back gracefully; the key continues to work via the
  `DAVINCI_IMAGE_AI_API_KEY` environment variable.

### Improved
- **Human-readable API error messages** – HTTP errors from the Gemini/Veo API
  now include plain-English explanations for common status codes (401, 403,
  429, 500, 503, etc.) in addition to the raw API message. Network failures
  (previously logged as "HTTP 000") now display a clear connectivity hint.
- Fixed inconsistent indentation in `load_settings()`.

---

## [0.4.18-bugfixes] – 2026-03

### Fixed
- Miscellaneous stability fixes and edge-case handling across image and video generation pipelines.
- Ref-slot undo (last-cleared-ref) state tracking.
- Gallery scroll sync guard flag (`gallery_scroll_sync`).

---

## [0.4.x] – 2026-02 / 2026-03 (early development)

Initial rapid development iterations:
- Gemini image generation via `gemini-2.5-flash-image` and related models.
- Veo 3 / Veo 3.1 video generation with polling loop.
- DaVinci Resolve timeline frame grab for reference images.
- Gallery viewer with pagination, history, and sidecar metadata.
- Settings persistence, debug logging, and Media Pool import.
- macOS clipboard (image + path) via `pbcopy` / AppleScript.
- Right-click context menu via `fusion:AskUser`.
