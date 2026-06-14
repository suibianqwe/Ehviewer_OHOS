# Migration Map

## Android To HarmonyOS Mapping

| Android area | Current source | HarmonyOS target |
| --- | --- | --- |
| Application startup | `EhApplication`, `SplashActivity`, `MainActivity` | `EntryAbility`, ArkUI pages |
| Activity and Fragment UI | `app/src/main/java/com/hippo/ehviewer/ui` | ArkUI pages/components |
| Gallery list/detail | `ui/scene/gallery`, `client/parser` | ArkTS list/detail services and pages |
| Network | OkHttp, request inspector, Conscrypt | HarmonyOS HTTP APIs with referer-aware GET/POST services |
| Cookies/session | Android cookie and OkHttp/WebView interceptors | ArkTS password sign-in, ArkWeb cookie capture and persistent cookie store |
| Database | GreenDAO generated DAO classes | HarmonyOS relational store |
| Preferences | AndroidX Preference, SharedPreferences | HarmonyOS preferences/data preferences |
| Download service | Android foreground service | HarmonyOS background task plus file APIs |
| File sharing | Android `FileProvider` | HarmonyOS file picker, sandbox and URI APIs |
| Biometrics | AndroidX Biometric | HarmonyOS user authentication APIs |
| Notifications | Android notification manager | HarmonyOS notification kit |
| WebView/recaptcha | Android WebView helpers | ArkWeb plus HarmonyOS web component |
| Native image code | JNI/CMake under `app/src/main/cpp` | HarmonyOS NDK/NAPI native module |

## Files Started In This Port

| File | Purpose |
| --- | --- |
| `build-profile.json5` | HarmonyOS product and API target |
| `AppScope/app.json5` | App bundle metadata |
| `entry/src/main/module.json5` | Entry HAP module and permissions |
| `entry/src/main/ets/entryability/EntryAbility.ets` | Main HarmonyOS ability |
| `entry/src/main/ets/pages/Index.ets` | ArkUI drawer/stage shell modeled after Android `MainActivity`, gallery list and detail scenes |
| `entry/src/main/ets/model/GalleryModels.ets` | Initial shared data contracts |
| `entry/src/main/ets/services/MigrationStatus.ets` | Visible migration checklist |
| `entry/src/main/ets/services/EhUrl.ets` | ArkTS port of core EhUrl, list URL and favorites URL builders |
| `entry/src/main/ets/services/GalleryListUrlParser.ets` | ArkTS port of gallery list URL parsing |
| `entry/src/main/ets/services/EhHttpClient.ets` | HarmonyOS HTTP wrapper using `@ohos.net.http`, password sign-in, gallery list pagination, detail loading and image-page loading |
| `entry/src/main/ets/services/EhCookieStore.ets` | Cookie header store backed by HarmonyOS preferences with explicit exception handling |
| `entry/src/main/ets/services/EhSettingsStore.ets` | HarmonyOS preferences-backed store for migrated Settings values |
| `entry/src/main/ets/services/EhWindowPrivacy.ets` | HarmonyOS window privacy bridge for the original secure-screen setting |
| `entry/src/main/ets/services/EhSpiderInfoStore.ets` | HarmonyOS preferences-backed SpiderInfo slice for reader showKey and page token reuse |
| `entry/src/main/ets/services/EhHistoryStore.ets` | HarmonyOS preferences-backed history list replacing the first slice of Android `EhDB` history DAO |
| `entry/src/main/ets/services/EhDownloadStore.ets` | HarmonyOS preferences-backed download queue replacing the first slice of Android `DownloadInfo` and `DownloadManager` state |
| `entry/src/main/ets/services/EhDownloadFileStore.ets` | HarmonyOS app-files gallery folder writer for downloaded page files and `.ehviewer` metadata |
| `entry/src/main/ets/services/GalleryPageCache.ets` | In-memory reader page cache used by the HarmonyOS reader and adjacent-page preloading |
| `entry/src/main/ets/services/GalleryListParser.ets` | ArkTS parser for minimal, extended and thumbnail gallery list rows |
| `entry/src/main/ets/services/GalleryListFixture.ets` | Local parser fixtures rendered by `HomePanel` |
| `entry/src/main/ets/services/GalleryDetailParser.ets` | Lightweight ArkTS parser for gallery detail metadata, tags and previews |
| `entry/src/main/ets/services/GalleryDetailFixture.ets` | Local gallery detail parser fixture |
| `entry/src/main/ets/services/GalleryPageParser.ets` | ArkTS parser for image page URL, original image URL and retry key |
| `entry/src/main/ets/services/GalleryPageApiParser.ets` | ArkTS parser for the original app's `api.php` `showpage` JSON fast path |
| `entry/src/main/ets/services/GalleryPageUrlParser.ets` | ArkTS parser for `/s/{pToken}/{gid}-{page}` reader page URLs |
| `entry/src/main/ets/services/ReaderImageCache.ets` | HarmonyOS app-cache image downloader modeled after the first local-cache layer of Android `SpiderDen` |
| `entry/src/main/ets/services/TopListParser.ets` | ArkTS port of the Android top-list parser for `toplist.php` ranking blocks |

## Next Implementation Slice

The next concrete slice should extend the same network/parser and storage path:

1. Wire persisted Settings values into more runtime systems: theme, downloader and privacy.
2. Add retry and empty-state polish to the gallery list, top-list and detail scenes.
3. Replace local parser fixtures with device-side parser tests once the test runner is configured.
4. Harden ArkWeb login for captcha-heavy flows and browser challenge recovery.
5. Connect the download queue to a HarmonyOS background image writer and app-file storage.
