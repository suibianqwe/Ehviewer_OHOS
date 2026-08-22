# EhViewer HarmonyOS Complete User Guide

English · [简体中文](USER_GUIDE.md)

This guide applies to EhViewer HarmonyOS `0.6.2`. Button positions may vary with the device, system version, window size, and permissions, but the entry points and behavior are the same. Portrait screenshots were captured on a phone and landscape screenshots on a tablet. Every reader screenshot in this guide was reached through `Subscriptions → Gallery details → Read`.

> Tip: the app follows the system proxy and language by default. On a working network, advanced options such as custom hosts, SNI fronting, and DoH are normally unnecessary.

## Contents

1. [Installation and first launch](#1-installation-and-first-launch)
2. [Login and site selection](#2-login-and-site-selection)
3. [Main interface](#3-main-interface)
4. [Browsing, list modes, and split view](#4-browsing-list-modes-and-split-view)
5. [Searching galleries](#5-searching-galleries)
6. [Gallery details and actions](#6-gallery-details-and-actions)
7. [Reader](#7-reader)
8. [Title, comment, and manga translation](#8-title-comment-and-manga-translation)
9. [Downloads and local reading](#9-downloads-and-local-reading)
10. [Favorites, history, tags, and comment blocklist](#10-favorites-history-tags-and-comment-blocklist)
11. [Appearance, language, and privacy](#11-appearance-language-and-privacy)
12. [Network and proxy](#12-network-and-proxy)
13. [Backup, restore, and Wi-Fi Direct transfer](#13-backup-restore-and-wi-fi-direct-transfer)
14. [Migrating downloads from the original EhViewer](#14-migrating-downloads-from-the-original-ehviewer)
15. [Updates, logs, and troubleshooting](#15-updates-logs-and-troubleshooting)

## 1. Installation and first launch

### 1.1 Downloading the app

1. Open the project's [GitHub Releases](https://github.com/suibianqwe/Ehviewer_OHOS/releases).
2. Download the latest `EhViewer_OHOS_version.hap`.
3. The package is an unsigned HAP. It can be installed with tools such as [Auto Installer](https://github.com/likuai2010/auto-installer).

The project targets API `26.0.0` and is compatible with API `6.0.0(20)`. Devices below API 23 can install it, but incompatible SNI fronting enhancements are automatically disabled.

### 1.2 Recommended first-launch setup

1. Read and accept the app's initial notice.
2. Open the side drawer and choose `Settings → EH`, then select E-Hentai or ExHentai.
3. Log in if you need favorites, subscriptions, My Tags, or ExHentai.
4. Configure the download location, worker count, and reader preload count under `Settings → Downloads`.
5. Enable title or manga translation under `Settings → Translation` only if needed.

## 2. Login and site selection

### 2.1 Selecting a site

Open `Settings → EH → Gallery site`:

- E-Hentai is the public site and is suitable for normal browsing.
- ExHentai requires valid account cookies and permission to access the site.

The selection affects home, search, favorites, gallery details, and metadata recovery. If metadata recovery from E-Hentai fails while a valid account is available, the app may retry through ExHentai.

### 2.2 Login methods

The app supports in-app login, web login, and cookie login. Logging out or clearing cookies requires confirmation.

- In-app login opens an ArkWeb page after the credentials are submitted. Complete any visible Cloudflare/Turnstile check manually; the app collects the identity cookies after the site finishes login.
- Web login opens the site's normal login flow. Do not repeatedly refresh a Cloudflare page; wait for verification and the automatic redirect.
- Cookie login accepts `ipb_member_id`, `ipb_pass_hash`, and `igneous` separately, or extracts them from a complete Cookie string.

If the web page remains signed in after an app logout, use the app's `Log out/Clear cookies` action first, then reopen web login.

<p align="center">
  <img src="images/account-settings-phone.jpg" width="360" alt="EH account and site settings on a phone" />
  <img src="images/account-config-phone.jpg" width="360" alt="Account configuration page on a phone" />
</p>

### 2.3 Refreshing account configuration after login

After a successful login, the app tries to open the current site's settings page and collect `uconfig` automatically. If gallery covers, reader images, or quota information still fail to load, do this before changing network options:

1. Open `Settings → EH → Account configuration`.
2. Wait until the page body appears, then return to the app. You normally do not need to press Apply on the website.
3. Return to the failed page and pull to refresh or tap the failed image.

This refreshes account-specific image loading, size, region, and filtering options. Repeat it after changing sites or logging in again if images stop loading. Identity cookies remain local. The local `igneous` value is never exported and is never replaced by an incoming backup or direct transfer.

## 3. Main interface

The main interface contains the title bar, gallery list, floating action button, and side drawer.

<p align="center">
  <img src="images/drawer-phone.jpg" width="360" alt="Side drawer on a phone" />
</p>

The drawer opens Home, Subscriptions, Popular, Toplists, Favorites, History, Downloads, and Settings. The floating action menu changes by page and may expose layout, filters, refresh, translation, or status controls.

Subscriptions show galleries matched by followed tags and are the starting point for the reader walkthrough in this guide.

<p align="center">
  <img src="images/subscriptions-phone.jpg" width="360" alt="Subscriptions on a phone" />
</p>

Common list gestures:

- Tap a card to open gallery details.
- Long-press a card for supported quick actions such as favorite, download, share, history removal, or multi-select.
- Pull down to refresh the current page.
- Scroll to the bottom to load another page.

## 4. Browsing, list modes, and split view

### 4.1 List modes

Open `Settings → EH → List mode` and choose:

- Details: cover, title, uploader, language, pages, rating, and category.
- Thumbnails: an equal-width waterfall whose height follows each image; rating and language can be hidden independently.
- Extended: the detail card plus a horizontally scrollable tag row.

Detail and Extended use the detail-size setting; Thumbnail uses the thumbnail-size setting. `Show tag translations` controls translated tag, language, and category labels.

### 4.2 Split view on wide screens

Enable `Settings → EH → Split view` on tablets, unfolded foldables, and PCs.

<p align="center">
  <img src="images/subscriptions-tablet.jpg" width="900" alt="Subscriptions on a landscape tablet" />
  <img src="images/gallery-detail-tablet.jpg" width="900" alt="Gallery details beside subscriptions on a tablet" />
</p>

- The left pane keeps the list or parent page; the right pane shows details or another child page.
- Drag the divider to resize the panes. Its position is shared across supported pages.
- Back first affects the pane that currently owns focus.
- The full-screen reader remains independent and never opens inside a pane.

## 5. Searching galleries

Use the search button in the title bar. Search supports keywords, uploader, tags, subscriptions, and advanced filters.

### 5.1 Keywords and multiple tags

Submit text for a normal search. Tapping a tag in gallery details opens the full search page and creates a removable tag condition. Add more tags to narrow the results, or remove an existing chip. Tapping an uploader creates a nested uploader search; Back restores the previous conditions, list position, and detail state.

### 5.2 Advanced search and saved searches

Use the advanced button beside the search field to select categories, name/tag/description/torrent scope, and other conditions. Save a useful combination as a search bookmark and restore it later from the bookmark row.

### 5.3 Image search

Select a photo or file, then choose Similar image or Cover search. The corresponding actions in gallery details reuse the same search page and route state.

## 6. Gallery details and actions

Gallery details contain the cover, titles, uploader, category, page count, size, date, rating, tags, comments, and previews.

<p align="center">
  <img src="images/gallery-detail-phone.jpg" width="360" alt="Gallery details on a phone" />
</p>

Common actions include:

- Favorite in a cloud or local favorite list.
- Submit a star rating.
- Open the HarmonyOS system share panel.
- View Torrent entries and copy a magnet link.
- Request an original/resampled archive or H@H download into the public Download root.
- Search for similar galleries or the current cover.
- Add the gallery to the download queue.
- Enter the full-screen reader.

Tap a tag to search it. Use the add button beside the tag section to enter tag editing and voting. Translated tag names and categories follow `Show tag translations`, independently of the app language.

## 7. Reader

The reader is always full screen. Tap the center to show or hide controls. Use the side regions to turn pages, double-tap for quick zoom, pinch for continuous zoom, and long-press the image for image actions.

<p align="center">
  <img src="images/reader-phone.jpg" width="300" alt="Phone reader opened from Subscriptions" />
  <img src="images/reader-layout-phone.jpg" width="300" alt="Reader layout tab" />
</p>

### 7.1 Direction, scaling, and display

The reader panel and `Settings → Reading` can configure:

- left-to-right, right-to-left, or top-to-bottom reading;
- original size, fit width, fit height, fit screen, or a fixed scale as allowed by the direction;
- default, portrait, landscape, sensor rotation, or match-image rotation;
- upscaling, SDR-to-HDR, full screen, keep screen on, custom brightness, and extra-dark mode;
- auto page turn, volume-key turn, translation, clock, progress, and battery overlays.

<p align="center">
  <img src="images/reader-display-phone.jpg" width="360" alt="Reader display settings" />
</p>

### 7.2 Adaptive two-page mode

When enabled, a portrait screen may place two suitable wide pages vertically, while a landscape screen may place two narrow pages side by side. This mode limits reading to horizontal directions, forces Fit screen, and disables Match image rotation.

### 7.3 Preloading and scheduling

`Settings → Downloads → Multi-thread downloads` controls the shared number of reader and download image workers. `Preload images` controls how many later reader pages are fetched. The current reader page has the highest priority and is not left behind a long background queue.

### 7.4 Reader presets

Open the Layout tab and choose Reader preset. A preset stores direction, scaling, rotation, two-page mode, border cropping, and image-processing settings. Create, save, update, rename, or delete custom presets. Built-in presets can be updated but not renamed or removed. Switching presets applies immediately.

### 7.5 Image adjustment and enhancement

- Moiré removal offers Off, Auto, Weak, Medium, and Strong. Auto considers the source size and target physical display size.
- Image adjustment controls exposure, brightness, contrast, highlights, shadows, clarity, sharpening, and related values.
- Upscaling targets the current display area. API 26 devices can use Core Vision AI; other environments use the system capability.
- SDR-to-HDR enhances brightness, highlights, and color on supported devices.
- Automatic white/black border cropping removes near-solid outer margins during pre-rendering without altering the original file.

These options can coexist. Pre-rendering follows `moiré removal and image adjustments → upscaling → HDR`. Cached results include target size and settings, and work outside the active pre-render range is released. A long-press save prefers the currently displayed processed result.

<p align="center">
  <img src="images/reader-adjustment-phone.jpg" width="360" alt="Moiré removal and image adjustments" />
</p>

## 8. Title, comment, and manga translation

Open `Settings → Translation`:

1. Enable Translation to show title, detail, and comment translation actions.
2. Enable Manga translation to show the edge-aligned reader button.
3. Select a target language and service.

Without AI translation, the app can use Google, Bing, Baidu, Youdao, MyMemory, or Lingva web services. AI translation supports DeepSeek, OpenAI, Gemini, and custom OpenAI-compatible endpoints. Custom endpoints can store multiple names, URLs, keys, and models.

Tap the reader translation button to show or hide the current gallery's translated overlays. Long-press it to rerun OCR and translation for the current page. Current, next, and following pages have priority. Downloaded results are stored with download metadata; online-reading results are stored in history. Leaving the reader cancels pending and interruptible work.

For OCR placement problems, enable OCR debug recording, reproduce once, export the record, and include the original image and a display screenshot in the issue.

## 9. Downloads and local reading

Use Download in gallery details or a card's long-press menu.

### 9.1 Download settings

- Location: app files or the public Downloads directory.
- Multi-thread downloads: a single shared worker count for reader and download tasks. Workers are calculated across all galleries; when the active gallery has fewer remaining images than available workers, the next queued gallery can start.
- Preload images: number of later reader images fetched early.
- Resolution/Original images: requested image size.
- Timeout, file order, and large-list pagination.

### 9.2 Download page

<p align="center">
  <img src="images/downloads-phone-redacted.jpg" width="360" alt="Phone download page with explicit R18 areas pixelated" />
</p>

- Tap a task to open its local details.
- Long-press a card to enter multi-select.
- Delete shows the selected count and asks for confirmation.
- The status filter chooses Waiting, Downloading, Completed, Failed, and other visible states.
- With no gallery selected, Download and Pause act on the galleries visible under the current status filter rather than every gallery.
- Export writes a ZIP to the public Download root.

Notifications show state, progress, and speed. Privacy mode hides gallery and file details.

### 9.3 Recovering download items

Open `Settings → Downloads → Recover download items`. The app scans gallery folders and unencrypted ZIP files in the public Download root. It can restore app exports, compatible legacy EhViewer ZIPs, and site archives whose gallery ID can be read from the filename. Unsupported, encrypted, or metadata-less archives are skipped without modification. A completion dialog reports recovered, processed, and skipped counts.

## 10. Favorites, history, tags, and comment blocklist

- Favorites supports cloud and local collections. Long-press a favorite for quick actions.
- Opening details writes history; reading progress and online manga translation results are stored there. Configure the maximum under `Settings → EH`.
- `Settings → EH → My Tags` manages subscribed and blocked tags and requires login.
- `Settings → EH → Filters` controls tag, uploader, keyword, and rating filters.
- The comment blocklist hides comments by exact username locally. It does not change website account data or block the user's uploads.

JSON backup, supported Android database import, and Wi-Fi Direct transfer can carry the comment blocklist. Incoming entries are merged by username.

## 11. Appearance, language, and privacy

`Settings → EH` supports light, dark, black, and follow-system themes, plus several theme colors. Open `Settings → Advanced → App language` for Follow system, English, Simplified Chinese, or Traditional Chinese. Tag translation is independent of the app language.

`Settings → Privacy` includes app authentication, screenshot/task-preview protection, private download notifications, saved error bodies, and crash logs. Enable diagnostic storage only while investigating a problem and clear it afterward.

## 12. Network and proxy

Keep defaults when the site works normally.

### 12.1 Proxy

`Settings → Advanced → Proxy` supports System, Direct/Bypass system proxy, HTTP, and SOCKS5. HTTP and SOCKS5 support server/port and optional authentication; SOCKS5 also supports exclusions and proxy DNS where compatible. Translation requests follow proxy settings but do not use EH-specific hosts, SNI, or direct-detection enhancements.

### 12.2 DoH, hosts, and SNI fronting

- DoH provides encrypted DNS through supported providers.
- Built-in hosts should be enabled only when normal DNS resolution fails.
- EX hosts only targets ExHentai-related names.
- SNI fronting is for networks that block SNI; speed tests and IP weighting apply only when it is enabled.
- Direct-connect detection keeps proxy and DoH behavior, but can bypass hosts/SNI enhancements when direct access works.

Run Network diagnostics after changing these options to test E-Hentai, ExHentai, the forum, and the project repository separately.

## 13. Backup, restore, and Wi-Fi Direct transfer

### 13.1 File backup

Under `Settings → Advanced`, Export data writes settings, history, download metadata, favorites, bookmarks, filters, and the comment blocklist to JSON. Import data accepts this backup and supported original Android databases. Export the current state before a large import.

### 13.2 Wi-Fi Direct transfer

Open `Settings → Advanced → Wi-Fi Direct transfer`. Choose Send on one nearby device and Receive on the other. The sender creates a Wi-Fi Direct group; the receiver scans and selects it. Keep both pages open until the application data channel finishes.

<p align="center">
  <img src="images/wifi-direct-tablet.jpg" width="900" alt="Wi-Fi Direct transfer on a landscape tablet" />
  <img src="images/wifi-direct-selection-phone.jpg" width="360" alt="Selecting multiple transfer categories on a phone" />
</p>

Multiple categories can be selected together:

- Reading progress is merged in both directions by latest real page-turn time; ties keep the larger page number.
- App settings and login cookies transfer portable preferences and login state. Device paths, file permissions, caches, and other device-specific state remain local.
- Search bookmarks, local favorites, and the comment blocklist merge into the receiver.
- Download records and images carry metadata and downloaded image files.

OCR translation results are not included in progress sync. Local `igneous` is never exported, and imports or incoming transfers ignore any supplied value so the receiver keeps its own persistent value.

## 14. Migrating downloads from the original EhViewer

<table>
  <tr>
    <td><img src="images/migration-source-download-folder.png" width="300" alt="Original Android download directory" /></td>
    <td><img src="images/migration-move-to-ehviewer.jpg" width="300" alt="Move galleries into the HarmonyOS directory" /></td>
    <td><img src="images/migration-restore-download-items.png" width="300" alt="Recover download items action" /></td>
  </tr>
  <tr>
    <td align="center">Find the old directory</td>
    <td align="center">Copy gallery folders</td>
    <td align="center">Run recovery</td>
  </tr>
</table>

1. In the file manager, locate the old directory, commonly `My phone → Compatible app data → EhViewer → download`.
2. Copy each gallery folder into the HarmonyOS-accessible `My phone → Download → EhViewer → EhViewer` directory.
3. Run `Settings → Downloads → Recover download items`.
4. Wait while the app recognizes folders, normalizes image names, and fetches missing metadata.

If only ZIP files are available, place supported unencrypted archives in the public Download root and run the same recovery action. Later downloads reorganize changed gallery and image names without downloading existing pages again.

## 15. Updates, logs, and troubleshooting

### 15.1 Updating

Use `Settings → About → Check for updates`, or visit [GitHub Releases](https://github.com/suibianqwe/Ehviewer_OHOS/releases). The tag translation database has a separate version check.

### 15.2 Covers or images do not load

1. First open `Settings → EH → Account configuration`, wait for the page to load, return, and retry the image.
2. Confirm that a browser can reach the selected site.
3. Check the proxy setting and run Network diagnostics.
4. Try DoH, built-in hosts, and SNI fronting one at a time only when needed.
5. Tap a failed image or pull to refresh after the network becomes ready.

### 15.3 ExHentai or quota does not load

1. Confirm that ExHentai is selected.
2. Open Account configuration and return after it loads.
3. Log in again and verify `ipb_member_id`, `ipb_pass_hash`, and the local `igneous`.
4. Run Network diagnostics, then enable hosts/SNI only if direct access fails.

### 15.4 Translation or OCR problems

Use Test translation under Translation settings. For web-service 403/rate limits, switch services or retry later. For AI providers, check the URL, key, model, and balance. For manga OCR placement, long-press the reader translation button, then collect OCR debug information if the problem remains.

### 15.5 Exporting diagnostic information

When reporting an issue, include:

- the page and exact reproduction steps;
- app version, device model, system version, and selected site;
- a screenshot or recording;
- `Settings → Advanced → Export logs`, with all private data removed;
- OCR debug export for manga translation issues when relevant.

Never publish account cookies, API keys, or other private information.

---

[Back to English README](../README_EN.md) · [Submit an issue](https://github.com/suibianqwe/Ehviewer_OHOS/issues) · [View releases](https://github.com/suibianqwe/Ehviewer_OHOS/releases)
