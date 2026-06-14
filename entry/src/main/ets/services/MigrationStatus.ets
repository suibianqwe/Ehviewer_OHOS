export interface MigrationTask {
  name: string;
  source: string;
  target: string;
  status: string;
}

export const migrationTasks: MigrationTask[] = [
  {
    name: 'Core models and URL builders',
    source: 'app/src/main/java/com/hippo/ehviewer/client/data',
    target: 'entry/src/main/ets/model',
    status: 'started: models, EhUrl, list/favorites URL builders'
  },
  {
    name: 'Network session and cookies',
    source: 'EhEngine, EhRequest, OkHttp helpers',
    target: 'HarmonyOS HTTP service',
    status: 'started: GET/POST client, password/Web/Cookie sign-in, persistent Cookie store, referer-aware loads, duplicate request coalescing, bounded text request pool, transient failure retry, per-call cache-control, system/custom proxy, DoH and built-in host rules, friendly HTTP/network diagnostics, short shared response cache, persisted SpiderInfo showKey cache and showpage API fast path'
  },
  {
    name: 'HTML and API parsers',
    source: 'client/parser',
    target: 'ArkTS parser services',
    status: 'started: GalleryListParser, GalleryDetailParser, GalleryPageParser and TopListParser'
  },
  {
    name: 'Gallery list and detail UI',
    source: 'ui/scene/gallery',
    target: 'ArkUI pages and components',
    status: 'started: Android-style drawer hierarchy, settings-hosted sign-in flows, list/detail scenes, top-list scene, action-card header controls; GalleryCommentsScene implemented with HTML stripping, comment previews in detail page and full CommentsScene navigation in GalleryListScene/HistoryScene/TopListScene'
  },
  {
    name: 'Settings hierarchy',
    source: 'SettingsActivity and res/xml/*_settings.xml',
    target: 'ArkUI SettingsScene',
    status: 'started: drawer matches Android nav_drawer_main; all setting panels implemented; UConfig/MyTags open in embedded WebView; Filter/Blacklist rules managed via EhFilterStore with local preferences persistence and applied to gallery list; Export/Import data via DocumentViewPicker (cookies, settings, history, downloads, filters bundled to JSON); Pattern protection via userIAM.userAuth biometric/PIN prompt on app foreground'
  },
  {
    name: 'Reader and image pipeline',
    source: 'glgallery, glview, native image code',
    target: 'ArkUI reader plus native image bridge',
    status: 'started: GalleryPageParser, showpage API parser, preview-to-reader entry, previous/next, retry, zoom, fit mode, original-image toggle, info panel, first-page warmup, page cache, in-flight page coalescing, previous-page referer handoff, reader/thumb image file cache, prioritized three-slot image queue, configurable image timeout, transient image retry, partial-file cleanup, sequential adjacent preload and reading-direction tap zones'
  },
  {
    name: 'History',
    source: 'HistoryScene, EhDB history DAO',
    target: 'ArkUI HistoryScene and HarmonyOS preferences store',
    status: 'started: viewed gallery details are persisted, listed, reopened, removed and cleared'
  },
  {
    name: 'Downloads and storage',
    source: 'download service and FileProvider',
    target: 'HarmonyOS background task and file APIs',
    status: 'started: preferences-backed download queue and labels, detail-page enqueue/remove, Downloads scene, search, status/label filters, sorting, foreground queue runner, resume existing page files, page/image fetch progress, app-files gallery folder output, start/stop-all state transitions and finished cleanup'
  }
];
