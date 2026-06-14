# EhViewer HarmonyOS Port

This directory is the HarmonyOS native port workspace for `Ehviewer_CN_SXJ`.

Target platform:

- HarmonyOS: 6.1.0
- API: 6.1.1(24)
- Runtime: native HarmonyOS app, not Android APK compatibility mode
- Language/UI: ArkTS + ArkUI Stage model

## Current Status

The Android project is large and cannot be mechanically converted into a working HarmonyOS app. The existing app contains:

- 532 Java/Kotlin source files
- Android Activity/Fragment/View based UI
- AndroidX, Material, Firebase, WebView, OkHttp, GreenDAO and many Android-only libraries
- JNI/C/C++ image and archive handling code
- Android services, providers, permissions and storage APIs

HarmonyOS 6 native apps need ArkTS/ArkUI, HarmonyOS application lifecycle, HarmonyOS permissions, HarmonyOS storage, and HarmonyOS native networking/database APIs. This workspace starts the native port without modifying the Android build.

## First Milestone

The first milestone is a runnable shell app with the original app's product shape:

- Home/gallery list placeholder
- Favorites placeholder
- Downloads placeholder
- Settings placeholder
- Shared data model stubs
- API 6.1.1(24) build target in `build-profile.json5`

## Migration Order

1. Core data models and URL builders
2. Network session, cookies and request retry policy
3. HTML/API parsers
4. Gallery list, search and favorites UI
5. Gallery detail UI
6. Image page loading and reader UI
7. Download queue and local storage
8. Archive import/export and native image decoders
9. Settings, security lock, Wi-Fi transfer and app update flow

## High Risk Areas

- Android `Activity`, `Fragment`, custom `View`, `RecyclerView`, OpenGL view and Material UI code must be rewritten in ArkUI.
- Android storage permissions and `FileProvider` need redesign around HarmonyOS file and picker APIs.
- Android `DownloadService` foreground service behavior must be mapped to HarmonyOS background task capabilities.
- GreenDAO database code should be replaced with HarmonyOS relational store APIs.
- OkHttp can not be assumed available in ArkTS. Use HarmonyOS HTTP APIs or a vetted OpenHarmony npm package.
- JNI image code may be reusable only after being adapted to HarmonyOS NDK/NAPI build rules.

## Open In DevEco Studio

Open the `harmonyos` directory as a HarmonyOS project. If DevEco Studio prompts to repair Hvigor or SDK versions, accept the repair and keep the target SDK at `6.1.1(24)`.

## Command Line Build

On this workstation, DevEco Studio is installed under `D:\Program Files\Huawei\DevEco Studio`. Hvigor needs both the SDK root and Java runtime in the shell environment:

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='D:\Program Files\Huawei\DevEco Studio\jbr\bin;' + $env:Path
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp
```

The project currently builds for HarmonyOS `6.1.0` with API `6.1.1(24)`. Unsigned package output is expected until a `signingConfigs` profile is added to `build-profile.json5`.

## Current Native Slice

The HarmonyOS app now includes an initial network and parsing path:

- `EhHttpClient.ets` wraps `@ohos.net.http` for text requests, gallery list loading and gallery detail loading.
- `EhHttpClient.ets` also ports the Android password sign-in form request, keeps referer-aware list/detail/image-page loads, coalesces duplicate in-flight GET and reader-page requests, keeps a short shared response cache for list/detail/page HTML, and uses the original app's `api.php` `showpage` fast path after a gallery show key is known.
- `EhCookieStore.ets` builds, absorbs, and persists Cookie headers through HarmonyOS preferences with explicit exception handling.
- `EhSpiderInfoStore.ets` persists reader SpiderInfo-style show keys and page tokens for a bounded recent-gallery set, so reopened galleries can skip the first full HTML reader-page fetch more often.
- `EhDownloadStore.ets` persists a first HarmonyOS download queue slice modeled after Android `DownloadInfo`, including state, labels, progress, archive URI and gallery metadata.
- `EhDownloadFileStore.ets` writes downloaded pages into app files under `downloads/{gid-title}` with original-style 8-digit page filenames and a `.ehviewer` metadata file, and can detect existing page files for resume.
- `GalleryListParser.ets` converts minimal, extended and thumbnail gallery list HTML into `GalleryInfo[]`.
- `GalleryDetailParser.ets` extracts gallery detail metadata, tags, comments and preview thumbnails.
- `GalleryPageParser.ets` extracts image page URLs, retry keys and original image links.
- `TopListParser.ets` extracts `toplist.php` ranking sections and feeds an ArkUI Top Lists scene modeled after the Android spinner/table screen.
- `ReaderImageCache.ets` downloads reader and thumbnail image bytes into the app cache directory with image-style request headers, a Conaco-like three-request concurrency cap, foreground reader priority, and a 320 MB disk-cache trim pass.
- `GalleryListFixture.ets` and `GalleryDetailFixture.ets` keep offline parser fixtures in the HarmonyOS workspace.
- The ArkUI shell follows the Android drawer/stage structure and routes Homepage, Subscription, What's Hot and Favourite through shared gallery list loading.
- The left drawer now matches Android `nav_drawer_main.xml`: Homepage, Subscription, What's Hot, Top Lists, Favourite, History, Downloads and Settings. Sign-in is no longer a top-level drawer item and is hosted under Settings/EH like the original app's account preferences.
- Settings now follows the original `settings_headers.xml` hierarchy with EH, Read, Download, Privacy, Advanced and About sections. Many migrated rows now cycle and persist through HarmonyOS preferences; sign-in/cookie/sign-out actions are wired, and the gallery-site value is used by list/detail/page requests.
- The Privacy > Secure screen setting now requests HarmonyOS `ohos.permission.PRIVACY_WINDOW` and applies `Window.setWindowPrivacyMode()` at startup, foreground resume, and when the preference is changed, matching the original Android anti-screenshot intent.
- History now has a native HarmonyOS scene backed by preferences. Successfully opened gallery details are recorded, deduplicated, capped by the migrated history-size setting, listed from the drawer, reopened, individually removed, or cleared.
- Downloads now has a native HarmonyOS scene backed by preferences. Detail-page Download actions enqueue/remove galleries, and the drawer Downloads page shows the queue with search, status and label filters, label add/delete, per-item label assignment, basic sorting, per-item state cycling/removal, foreground queue execution, resume/skip of existing page files, page/image fetch progress, app-files gallery folder output, start/stop-all state transitions and finished cleanup.
- Top Lists now loads the E-Hentai ranking page, switches among the seven original categories, opens gallery-list periods, and opens ranked gallery details when the ranked entry is a gallery URL.
- The detail scene now uses an Android-style action-card header for Download/Read. Read opens the first preview page and the reader has previous/next navigation backed by `GalleryPageParser`.
- The reader now includes a compact toolbar for retry, information, zoom, fit-mode cycling, and original/resampled image selection. Fit mode is backed by the migrated `page_scaling` setting.
- The reader now caches parsed image pages in memory, warms the first reader page after detail load, preloads adjacent pages sequentially according to the migrated `preload_image` setting, passes the previous reader page as referer for adjacent loads, coalesces duplicated in-flight page requests, stores reader images in the local app cache before switching to local display, and maps left/right tap zones through the migrated `reading_direction` setting. Gallery thumbnails also reuse the same local image cache.
- The first launch opens the sign-in scene. It now follows the Android login shape: username/password form first, separate WebView login, separate Cookie login, and guest mode.

The parser is intentionally conservative and does not yet cover every E-Hentai detail edge case. The next hardening step is to wire more persisted Settings values into runtime behavior, add device-side parser tests, add retry and empty-state polish beyond the reader, harden ArkWeb browser-challenge recovery, and move the foreground download runner into a HarmonyOS background task with gallery-folder file output.
