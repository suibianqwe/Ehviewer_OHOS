import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, GalleryTagInfo, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore, ReadingProgressBackupInfo } from '../services/EhHistoryStore';
import { BrowsePositionsBackupInfo } from '../services/EhBrowsePositionStore';
import {
  DEFAULT_DOWNLOAD_LABEL_ASK,
  DEFAULT_DOWNLOAD_LABEL_SETTING_KEY,
  FLOATING_ACTION_HOLDING_HAND_SETTING_KEY,
  HISTORY_INFO_SIZE_KEY,
  MULTI_DEVICE_CONTINUATION_SETTING_KEY,
  ehSettingsStore,
  historyInfoSizeLimitFromValue,
  historyInfoSizeOptions,
  normalizeHistoryInfoSizeOption,
  SettingEntry,
} from '../services/EhSettingsStore';
import { GalleryListLoadResult, NetworkDiagnosticResult } from '../services/EhHttpClient';
import { EhUrl, ListMode } from '../services/EhUrl';
import {
  ImageDownloadOptions,
  IMAGE_DOWNLOAD_PRIORITY_BACKGROUND,
  IMAGE_DOWNLOAD_PRIORITY_READER,
  readerImageCache,
} from '../services/ReaderImageCache';
import { previewThumbnailCache } from '../services/PreviewThumbnailCache';
import { FilterRule, ehFilterStore } from '../services/EhFilterStore';
import { CommentBlacklistBackupEntry } from '../services/EhCommentBlacklistStore';
import { readerSuperResolutionEngineOptions } from '../services/ReaderSuperResolutionSupport';
import { LocalFavoriteBackupInfo } from '../services/EhLocalFavoritesStore';
import { SearchBookmarkBackupInfo } from '../services/EhBookmarkStore';
import { EH_AUTHOR_NAME, EH_RELEASE_TAG } from '../services/EhBuildInfo';
import { normalizeGalleryLanguageCode } from '../services/GalleryLanguageSupport';
import {
  findSavedTranslationApi,
  parseSavedTranslationApis,
} from '../services/TranslationSupport';
import { decodeHtmlEntities } from './HtmlEntitySupport';
import {
  currentDarkModeThemeName as themeCurrentDarkModeThemeName,
  currentThemeName as themeCurrentThemeName,
  isBlackTheme as themeIsBlackTheme,
  isDarkTheme as themeIsDarkTheme,
  themeDividerColor as paletteDividerColor,
  themeDownloadStateActiveColor as paletteDownloadStateActiveColor,
  themeDownloadStateDoneColor as paletteDownloadStateDoneColor,
  themeDownloadStateFailedColor as paletteDownloadStateFailedColor,
  themeDownloadStateIdleColor as paletteDownloadStateIdleColor,
  themeDownloadStateWaitColor as paletteDownloadStateWaitColor,
  themeFieldBackground as paletteFieldBackground,
  themeMutedText as paletteMutedText,
  themePageBackground as palettePageBackground,
  themePlaceholderColor as palettePlaceholderColor,
  themePrimaryColor as palettePrimaryColor,
  themePrimaryText as palettePrimaryText,
  themeSecondaryText as paletteSecondaryText,
  themeSelectedBackground as paletteSelectedBackground,
  themeSelectedBackgroundLight as paletteSelectedBackgroundLight,
  themeSurface as paletteSurface,
  themeSurfaceVariant as paletteSurfaceVariant,
  themeTertiaryText as paletteTertiaryText,
} from './EhTheme';
import {
  notifyHistoryReadChanged,
  shouldShowTagTranslations,
  uiText,
} from './EhTranslations';
export {
  LANGUAGE_REVISION_KEY,
  THEME_REVISION_KEY,
  HISTORY_READ_REVISION_KEY,
  GALLERY_TITLE_REVISION_KEY,
  notifyLanguageChanged,
  notifyThemeChanged,
  notifyHistoryReadChanged,
  notifyGalleryTitleChanged,
  shouldUseChineseUi,
  shouldShowTagTranslations,
  uiText,
  uiValue,
  plainTextFromHtml,
  uiStatusText,
  uiPageText,
  zhText,
} from './EhTranslations';
export interface EhBackupBundle {
  version: number;
  exportedAt: string;
  cookies: string;
  settings: SettingEntry[];
  history: GalleryInfo[];
  readingProgress?: ReadingProgressBackupInfo[];
  searchHistory?: string[];
  browsePositions?: BrowsePositionsBackupInfo;
  downloadItems: DownloadInfo[];
  downloadLabels: DownloadLabel[];
  filterRules: FilterRule[];
  localFavorites?: LocalFavoriteBackupInfo[];
  bookmarks?: SearchBookmarkBackupInfo[];
  commentBlacklist?: CommentBlacklistBackupEntry[];
}

export const IDENTITY_AUTH_LOCKED_KEY: string = 'ehviewer_identity_auth_locked';
export const IDENTITY_AUTH_OFF: string = 'Off';
export const IDENTITY_AUTH_FINGERPRINT_FIRST: string = 'Fingerprint first';
export const IDENTITY_AUTH_FACE_FIRST: string = 'Face first';
export const IDENTITY_AUTH_PASSWORD_FIRST: string = 'Password first';

export interface DrawerItem {
  route: GalleryRoute;
  title: string;
  icon: string;
  subtitle: string;
}

export interface SettingsHeaderItem {
  panel: SettingsPanel;
  title: string;
  icon: string;
  summary: string;
}

interface ThumbnailReadyDelivery {
  path: string;
  onReady: (path: string) => void;
}

const THUMBNAIL_READY_BATCH_SIZE: number = 1;
const THUMBNAIL_READY_BATCH_DELAY_MS: number = 48;
const THUMBNAIL_RETRY_LIMIT: number = 2;
const THUMBNAIL_READY_QUEUE: ThumbnailReadyDelivery[] = [];
let thumbnailReadyScheduled: boolean = false;

export interface SettingsRowItem {
  key?: string;
  title: string;
  summary: string;
  value: string;
  type: string;
  options?: string[];
  optionDescriptions?: string[];
}

export enum SessionMode {
  Password = 'password',
  Cookie = 'cookie',
  Web = 'web'
}

export enum SettingsPanel {
  Main = 'main',
  Eh = 'eh',
  Read = 'read',
  Download = 'download',
  Privacy = 'privacy',
  Translation = 'translation',
  TranslationPrompt = 'translation_prompt',
  ReaderPresets = 'reader_presets',
  Advanced = 'advanced',
  WifiTransfer = 'wifi_transfer',
  RemoteStorage = 'remote_storage',
  About = 'about',
  Session = 'session',
  WebView = 'webview',
  Filter = 'filter',
  CommentBlacklist = 'comment_blacklist',
  MyTags = 'mytags'
}

export const DRAWER_ITEMS: DrawerItem[] = [
  { route: GalleryRoute.Home, title: 'Homepage', icon: 'H', subtitle: 'Gallery list and search' },
  { route: GalleryRoute.Subscription, title: 'Subscription', icon: 'S', subtitle: 'Watched tags' },
  { route: GalleryRoute.WhatsHot, title: 'What\'s Hot', icon: 'F', subtitle: 'Popular galleries' },
  { route: GalleryRoute.TopLists, title: 'Top Lists', icon: 'T', subtitle: 'Ranking tables' },
  { route: GalleryRoute.Favorites, title: 'Favourite', icon: 'L', subtitle: 'Cloud and local favorites' },
  { route: GalleryRoute.History, title: 'History', icon: 'R', subtitle: 'Recent reading' },
  { route: GalleryRoute.Downloads, title: 'Downloads', icon: 'D', subtitle: 'Queue and labels' },
  { route: GalleryRoute.Settings, title: 'Settings', icon: 'G', subtitle: 'Preferences' }
];

export const SETTINGS_HEADERS: SettingsHeaderItem[] = [
  { panel: SettingsPanel.Eh, title: 'EH', icon: 'E', summary: 'Account, site, gallery list and comments' },
  { panel: SettingsPanel.Read, title: 'Read', icon: 'R', summary: 'Reader direction, scaling and screen behavior' },
  { panel: SettingsPanel.Download, title: 'Download', icon: 'D', summary: 'Location, threads, preload and cleanup' },
  { panel: SettingsPanel.Privacy, title: 'Privacy', icon: 'P', summary: 'Lock and local data controls' },
  { panel: SettingsPanel.Translation, title: 'Translation', icon: 'T', summary: 'Title and comment translation providers' },
  { panel: SettingsPanel.Advanced, title: 'Advanced', icon: 'A', summary: 'Network, cache, hosts and diagnostics' },
  { panel: SettingsPanel.About, title: 'About', icon: 'I', summary: 'Version and license' }
];

let activeBackHandler: (() => boolean) | null = null;
let readerActiveBackHandler: (() => boolean) | null = null;
const ACTIVE_BACK_HANDLERS: Array<() => boolean> = [];
const DETAIL_BACK_HANDLERS: Array<() => boolean> = [];

export function setActiveBackHandler(handler: (() => boolean) | null): void {
  activeBackHandler = handler;
}

export function pushActiveBackHandler(handler: () => boolean): () => void {
  ACTIVE_BACK_HANDLERS.push(handler);
  return () => {
    for (let i = ACTIVE_BACK_HANDLERS.length - 1; i >= 0; i--) {
      if (ACTIVE_BACK_HANDLERS[i] === handler) {
        ACTIVE_BACK_HANDLERS.splice(i, 1);
        return;
      }
    }
  };
}

export function runActiveBackHandler(): boolean {
  const handlers = ACTIVE_BACK_HANDLERS.slice();
  for (let i = handlers.length - 1; i >= 0; i--) {
    if (handlers[i]()) {
      return true;
    }
  }
  if (handlers.length > 0) {
    return false;
  }
  return activeBackHandler !== null && activeBackHandler();
}

export function setReaderActiveBackHandler(handler: (() => boolean) | null): void {
  readerActiveBackHandler = handler;
}

export function runReaderActiveBackHandler(): boolean {
  return readerActiveBackHandler !== null && readerActiveBackHandler();
}

export function pushDetailBackHandler(handler: () => boolean): () => void {
  DETAIL_BACK_HANDLERS.push(handler);
  return () => {
    for (let i = DETAIL_BACK_HANDLERS.length - 1; i >= 0; i--) {
      if (DETAIL_BACK_HANDLERS[i] === handler) {
        DETAIL_BACK_HANDLERS.splice(i, 1);
        return;
      }
    }
  };
}

export function runDetailBackHandler(): boolean {
  for (let i = DETAIL_BACK_HANDLERS.length - 1; i >= 0; i--) {
    if (DETAIL_BACK_HANDLERS[i]()) {
      return true;
    }
  }
  return false;
}
export const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';
export const TOP_AVOID_HEIGHT_KEY: string = 'topAvoidHeight';
export const BOTTOM_AVOID_HEIGHT_KEY: string = 'bottomAvoidHeight';

export function createEmptyGallery(): GalleryInfo {
  return {
    gid: 0,
    token: '',
    title: '',
    category: GalleryCategory.Unknown,
    rating: -1,
    rated: false,
    pages: 0,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -2
  };
}

export function createEmptyDownloadInfo(): DownloadInfo {
  return {
    gid: 0,
    token: '',
    title: '',
    category: GalleryCategory.Unknown,
    rating: -1,
    rated: false,
    pages: 0,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -2,
    state: DownloadState.None,
    legacy: 0,
    time: 0,
    label: '',
    archiveUri: '',
    speed: 0,
    remaining: 0,
    finished: 0,
    downloaded: 0,
    total: 0,
    fileSize: -1
  };
}

export function createDetailFromGallery(gallery: GalleryInfo): GalleryDetail {
  const detail = createEmptyDetail();
  detail.gid = gallery.gid;
  detail.token = gallery.token;
  detail.title = gallery.title;
  detail.titleJpn = gallery.titleJpn;
  detail.thumb = gallery.thumb;
  detail.category = gallery.category;
  detail.posted = gallery.posted;
  detail.uploader = gallery.uploader;
  detail.rating = gallery.rating;
  detail.rated = gallery.rated;
  detail.pages = gallery.pages;
  detail.thumbWidth = gallery.thumbWidth;
  detail.thumbHeight = gallery.thumbHeight;
  detail.favoriteSlot = gallery.favoriteSlot;
  detail.favoriteName = gallery.favoriteName;
  detail.simpleLanguage = gallery.simpleLanguage;
  detail.simpleTags = cloneStringArray(gallery.simpleTags);
  detail.tagList = cloneStringArray(gallery.tagList);
  detail.detailLanguage = gallery.detailLanguage;
  detail.detailTags = gallery.detailTags === undefined ? undefined : cloneGalleryTagGroups(gallery.detailTags);
  if (gallery.detailLanguage !== undefined && gallery.detailLanguage.length > 0) {
    detail.language = gallery.detailLanguage;
  }
  if (gallery.detailTags !== undefined && gallery.detailTags.length > 0) {
    detail.tags = cloneGalleryTagGroups(gallery.detailTags);
  }
  return detail;
}

export function createEmptyDetail(): GalleryDetail {
  return {
    gid: 0,
    token: '',
    title: '',
    category: GalleryCategory.Unknown,
    rating: -1,
    rated: false,
    pages: 0,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -2,
    apiUid: -1,
    apiKey: '',
    tags: [],
    comments: [],
    torrentCount: 0,
    torrentUrl: '',
    archiveUrl: '',
    parent: '',
    visible: '',
    language: '',
    size: '',
    favoriteCount: 0,
    isFavorited: false,
    ratingCount: 0,
    previewPages: 0,
    previewSet: []
  };
}

export function createEmptyPreview(): GalleryPreview {
  return {
    index: 0,
    pageUrl: '',
    imageUrl: '',
    width: 0,
    height: 0,
    xOffset: 0,
    yOffset: 0
  };
}

export function createEmptyPage(): GalleryPage {
  return {
    pageUrl: '',
    imageUrl: '',
    skipHathKey: '',
    originImageUrl: '',
    showKey: ''
  };
}

export function createEmptyTopListDetail(): TopListDetail {
  return {
    title: '',
    lists: []
  };
}

export function createEmptyTopListInfo(): TopListInfo {
  return {
    kind: TopListKind.Gallery,
    title: 'Gallery Toplists',
    buckets: []
  };
}

export function createEmptyTopListBucket(): TopListBucket {
  return {
    title: '',
    follow: '',
    items: []
  };
}

export function createEmptyTopListItem(): TopListItem {
  return {
    href: '',
    gid: '',
    token: '',
    tag: '',
    value: ''
  };
}

function cloneStringArray(values: string[] | undefined): string[] | undefined {
  if (values === undefined) {
    return undefined;
  }
  const result: string[] = [];
  for (let i = 0; i < values.length; i++) {
    result.push(values[i]);
  }
  return result;
}

function cloneRequiredStringArray(values: string[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < values.length; i++) {
    result.push(values[i]);
  }
  return result;
}

function cloneOptionalGalleryTagGroups(groups: GalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: cloneRequiredStringArray(groups[i].tags)
    });
  }
  return result;
}

function findLanguageInTagGroups(groups: GalleryTagGroup[] | undefined): string {
  if (groups === undefined) {
    return '';
  }
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].namespace.toLowerCase() === 'language' && groups[i].tags.length > 0) {
      return groups[i].tags[0];
    }
  }
  return '';
}

function findLanguageInTags(tags: string[] | undefined): string {
  if (tags === undefined) {
    return '';
  }
  for (let i = 0; i < tags.length; i++) {
    const tag = tags[i];
    const lower = tag.toLowerCase();
    if (lower.indexOf('language:') === 0 && tag.length > 9) {
      return tag.substring(9);
    }
  }
  return '';
}

export function gallerySimpleLanguage(gallery: GalleryInfo): string {
  if (gallery.simpleLanguage !== undefined && gallery.simpleLanguage.length > 0) {
    return normalizedGalleryLanguageDisplay(gallery.simpleLanguage);
  }
  if (gallery.detailLanguage !== undefined && gallery.detailLanguage.length > 0) {
    return normalizedGalleryLanguageDisplay(gallery.detailLanguage);
  }
  const groupLanguage = findLanguageInTagGroups(gallery.detailTags);
  if (groupLanguage.length > 0) {
    return normalizedGalleryLanguageDisplay(groupLanguage);
  }
  const listLanguage = findLanguageInTags(gallery.tagList);
  if (listLanguage.length > 0) {
    return normalizedGalleryLanguageDisplay(listLanguage);
  }
  return normalizedGalleryLanguageDisplay(findLanguageInTags(gallery.simpleTags));
}

function normalizedGalleryLanguageDisplay(value: string): string {
  const code = normalizeGalleryLanguageCode(value);
  return code.length > 0 ? code : value;
}

function galleryDetailLanguage(gallery: GalleryInfo): string | undefined {
  const detail = gallery as GalleryDetail;
  if (detail.language !== undefined && detail.language.length > 0) {
    return detail.language;
  }
  if (gallery.detailLanguage !== undefined && gallery.detailLanguage.length > 0) {
    return gallery.detailLanguage;
  }
  const language = gallerySimpleLanguage(gallery);
  return language.length > 0 ? language : undefined;
}

function galleryDetailTags(gallery: GalleryInfo): GalleryTagGroup[] | undefined {
  const detail = gallery as GalleryDetail;
  if (detail.tags !== undefined && detail.tags.length > 0) {
    return cloneOptionalGalleryTagGroups(detail.tags);
  }
  return cloneOptionalGalleryTagGroups(gallery.detailTags);
}

export function cloneGalleryInfo(gallery: GalleryInfo): GalleryInfo {
  const language = gallerySimpleLanguage(gallery);
  return {
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn,
    thumb: gallery.thumb,
    category: gallery.category,
    posted: gallery.posted,
    uploader: gallery.uploader,
    rating: gallery.rating,
    rated: gallery.rated,
    simpleLanguage: language.length > 0 ? language : undefined,
    simpleTags: cloneStringArray(gallery.simpleTags),
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: gallery.favoriteSlot,
    favoriteName: gallery.favoriteName,
    tagList: cloneStringArray(gallery.tagList),
    detailTags: galleryDetailTags(gallery),
    detailLanguage: galleryDetailLanguage(gallery)
  };
}

export function cloneGalleryInfos(galleries: GalleryInfo[]): GalleryInfo[] {
  const result: GalleryInfo[] = [];
  for (let i = 0; i < galleries.length; i++) {
    result.push(cloneGalleryInfo(galleries[i]));
  }
  return result;
}

export function padTwo(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

export function applyGalleryFilters(galleries: GalleryInfo[]): GalleryInfo[] {
  const filtered: GalleryInfo[] = [];
  for (let i = 0; i < galleries.length; i++) {
    if (!ehFilterStore.isFiltered(galleries[i])) {
      filtered.push(galleries[i]);
    }
  }
  return filtered;
}

function cloneGalleryTagGroups(groups: GalleryTagGroup[]): GalleryTagGroup[] {
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: cloneRequiredStringArray(groups[i].tags),
      tagInfos: cloneGalleryTagInfos(groups[i].tagInfos)
    });
  }
  return result;
}

function cloneGalleryTagInfos(infos: GalleryTagInfo[] | undefined): GalleryTagInfo[] | undefined {
  if (infos === undefined) {
    return undefined;
  }
  const result: GalleryTagInfo[] = [];
  for (let i = 0; i < infos.length; i++) {
    result.push({
      id: infos[i].id,
      namespace: infos[i].namespace,
      tag: infos[i].tag,
      fullTag: infos[i].fullTag,
      voteUpEd: infos[i].voteUpEd,
      voteDownEd: infos[i].voteDownEd
    });
  }
  return result;
}

function cloneGalleryComments(comments: GalleryComment[]): GalleryComment[] {
  const result: GalleryComment[] = [];
  for (let i = 0; i < comments.length; i++) {
    result.push({
      id: comments[i].id,
      user: comments[i].user,
      posted: comments[i].posted,
      content: comments[i].content,
      score: comments[i].score,
      voteUpAble: comments[i].voteUpAble,
      voteUpEd: comments[i].voteUpEd,
      voteDownAble: comments[i].voteDownAble,
      voteDownEd: comments[i].voteDownEd,
      voteState: comments[i].voteState
    });
  }
  return result;
}

export function cloneGalleryPreviews(previews: GalleryPreview[]): GalleryPreview[] {
  const result: GalleryPreview[] = [];
  for (let i = 0; i < previews.length; i++) {
    result.push({
      index: previews[i].index,
      pageUrl: previews[i].pageUrl,
      imageUrl: previews[i].imageUrl,
      width: previews[i].width,
      height: previews[i].height,
      xOffset: previews[i].xOffset,
      yOffset: previews[i].yOffset
    });
  }
  return result;
}

export function cloneGalleryDetail(detail: GalleryDetail): GalleryDetail {
  const base = cloneGalleryInfo(detail);
  return {
    gid: base.gid,
    token: base.token,
    title: base.title,
    titleJpn: base.titleJpn,
    thumb: base.thumb,
    category: base.category,
    posted: base.posted,
    uploader: base.uploader,
    rating: base.rating,
    rated: base.rated,
    simpleLanguage: base.simpleLanguage,
    simpleTags: base.simpleTags,
    pages: base.pages,
    thumbWidth: base.thumbWidth,
    thumbHeight: base.thumbHeight,
    favoriteSlot: base.favoriteSlot,
    favoriteName: base.favoriteName,
    tagList: base.tagList,
    detailTags: cloneGalleryTagGroups(detail.tags),
    detailLanguage: detail.language,
    apiUid: detail.apiUid,
    apiKey: detail.apiKey,
    tags: cloneGalleryTagGroups(detail.tags),
    comments: cloneGalleryComments(detail.comments),
    torrentCount: detail.torrentCount,
    torrentUrl: detail.torrentUrl,
    archiveUrl: detail.archiveUrl,
    parent: detail.parent,
    visible: detail.visible,
    language: detail.language,
    size: detail.size,
    favoriteCount: detail.favoriteCount,
    isFavorited: detail.isFavorited,
    ratingCount: detail.ratingCount,
    previewPages: detail.previewPages,
    previewSet: cloneGalleryPreviews(detail.previewSet)
  };
}

export function cloneGalleryPage(page: GalleryPage): GalleryPage {
  return {
    pageUrl: page.pageUrl,
    imageUrl: page.imageUrl,
    skipHathKey: page.skipHathKey,
    originImageUrl: page.originImageUrl,
    showKey: page.showKey,
    cachedImagePath: page.cachedImagePath,
    cachedOriginImagePath: page.cachedOriginImagePath
  };
}

export function createReaderLoadingPage(pageUrl: string): GalleryPage {
  return {
    pageUrl: pageUrl,
    imageUrl: '',
    skipHathKey: '',
    originImageUrl: '',
    showKey: ''
  };
}

function cloneTopListItem(item: TopListItem): TopListItem {
  return {
    href: item.href,
    gid: item.gid,
    token: item.token,
    tag: item.tag,
    value: item.value
  };
}

function cloneTopListBucket(bucket: TopListBucket): TopListBucket {
  const items: TopListItem[] = [];
  for (let i = 0; i < bucket.items.length; i++) {
    items.push(cloneTopListItem(bucket.items[i]));
  }
  return {
    title: bucket.title,
    follow: bucket.follow,
    items: items
  };
}

function cloneTopListInfo(info: TopListInfo): TopListInfo {
  const buckets: TopListBucket[] = [];
  for (let i = 0; i < info.buckets.length; i++) {
    buckets.push(cloneTopListBucket(info.buckets[i]));
  }
  return {
    kind: info.kind,
    title: info.title,
    buckets: buckets
  };
}

export function cloneTopListDetail(detail: TopListDetail): TopListDetail {
  const lists: TopListInfo[] = [];
  for (let i = 0; i < detail.lists.length; i++) {
    lists.push(cloneTopListInfo(detail.lists[i]));
  }
  return {
    title: detail.title,
    lists: lists
  };
}

export function getAbilityContext(): common.UIAbilityContext | undefined {
  return AppStorage.get<common.UIAbilityContext>('abilityContext');
}

export function saveGalleryToHistory(gallery: GalleryInfo): void {
  const limit = currentHistoryInfoSizeLimit();
  const context = getAbilityContext();
  if (context === undefined) {
    ehHistoryStore.addGallery(gallery, limit);
    return;
  }
  ehHistoryStore.ensureLoaded(context).then(() => {
    ehHistoryStore.addGallery(gallery, limit);
    ehHistoryStore.save(context).catch(() => {});
  }).catch(() => {});
}

export function saveGalleryReadPosition(gid: number, pageIndex: number, gallery?: GalleryInfo): void {
  const limit = currentHistoryInfoSizeLimit();
  const context = getAbilityContext();
  if (context === undefined) {
    if (gallery !== undefined) {
      ehHistoryStore.addGallery(gallery, limit);
    }
    ehHistoryStore.setReadPage(gid, pageIndex);
    notifyHistoryReadChanged();
    return;
  }
  ehHistoryStore.ensureLoaded(context).then(() => {
    if (gallery !== undefined) {
      ehHistoryStore.addGallery(gallery, limit);
    }
    ehHistoryStore.setReadPage(gid, pageIndex);
    notifyHistoryReadChanged();
    ehHistoryStore.save(context).catch(() => {});
  }).catch(() => {});
}

export function currentHistoryInfoSizeLimit(): number {
  return historyInfoSizeLimitFromValue(ehSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
}

export function readerStartIndex(detail: GalleryDetail): number {
  const total = detail.pages > 0 ? detail.pages : detail.previewSet.length;
  if (total <= 0) {
    return 0;
  }
  const saved = ehHistoryStore.getReadPage(detail.gid);
  if (saved >= 0 && saved < total) {
    return saved;
  }
  return 0;
}

export async function readerStartIndexAsync(detail: GalleryDetail): Promise<number> {
  const context = getAbilityContext();
  if (context !== undefined) {
    await ehHistoryStore.ensureLoaded(context).catch(() => {});
  }
  return readerStartIndex(detail);
}

export function downloadButtonText(gid: number): string {
  return ehDownloadStore.contains(gid) ? 'Queued' : 'Download';
}

export function defaultDownloadLabelChoice(): string {
  const value = ehSettingsStore.getValue(DEFAULT_DOWNLOAD_LABEL_SETTING_KEY, DEFAULT_DOWNLOAD_LABEL_ASK);
  if (value === DEFAULT_DOWNLOAD_LABEL_ASK || value.length === 0 || ehDownloadStore.hasLabel(value)) {
    return value;
  }
  return DEFAULT_DOWNLOAD_LABEL_ASK;
}

export function saveDefaultDownloadLabelChoice(value: string): void {
  const normalized = value === DEFAULT_DOWNLOAD_LABEL_ASK ? value : value.trim();
  if (normalized !== DEFAULT_DOWNLOAD_LABEL_ASK && normalized.length > 0 && !ehDownloadStore.hasLabel(normalized)) {
    return;
  }
  ehSettingsStore.setValue(DEFAULT_DOWNLOAD_LABEL_SETTING_KEY, normalized);
  const context = getAbilityContext();
  if (context !== undefined) {
    ehSettingsStore.save(context).catch(() => {});
  }
}

export function toggleGalleryDownload(gallery: GalleryInfo, label: string = ''): boolean {
  if (ehDownloadStore.contains(gallery.gid)) {
    ehDownloadStore.removeGallery(gallery.gid);
    saveDownloadsQuietly();
    return false;
  }

  const item = ehDownloadStore.addGallery(gallery, label);
  if (item !== null) {
    ehDownloadStore.startGallery(item.gid);
  }
  saveDownloadsQuietly();
  return true;
}

export function saveDownloadsQuietly(): void {
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehDownloadStore.save(context).catch(() => {});
}

export const DOWNLOAD_STATUS_FILTER_OPTIONS: string[] = [
  'Idle', 'Waiting', 'Downloading', 'Downloaded', 'Failed', 'Updating', 'Invalid'
];

export function filterDownloadItems(items: DownloadInfo[], query: string, statusFilters: string[], labelFilter: string,
  sortMode: string, categoryFilter: string = 'All'): DownloadInfo[] {
  const normalizedQuery = query.toLowerCase().trim();
  const filtered: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const stateLabel = downloadStateLabel(item.state);
    const statusMatched = statusFilters.indexOf(stateLabel) >= 0;
    if (!statusMatched) {
      continue;
    }
    if (labelFilter !== '__all__' && item.label !== labelFilter) {
      continue;
    }
    if (categoryFilter !== 'All' && categoryName(item.category) !== categoryFilter) {
      continue;
    }
    if (normalizedQuery.length > 0 && !downloadItemMatches(item, normalizedQuery)) {
      continue;
    }
    filtered.push(item);
  }
  sortDownloadItems(filtered, sortMode);
  return filtered;
}

function downloadItemMatches(item: DownloadInfo, query: string): boolean {
  const title = item.title.toLowerCase();
  const uploader = item.uploader === undefined ? '' : item.uploader.toLowerCase();
  const label = item.label.toLowerCase();
  return title.indexOf(query) >= 0 || uploader.indexOf(query) >= 0 || label.indexOf(query) >= 0 ||
    item.gid.toString().indexOf(query) >= 0;
}

export function sortDownloadItems(items: DownloadInfo[], sortMode: string): void {
  items.sort((left: DownloadInfo, right: DownloadInfo): number => {
    if (sortMode === 'GID asc') {
      return left.gid - right.gid;
    }
    if (sortMode === 'GID desc') {
      return right.gid - left.gid;
    }
    if (sortMode === 'Rating desc') {
      return right.rating - left.rating;
    }
    if (sortMode === 'Rating asc') {
      return left.rating - right.rating;
    }
    if (sortMode === 'Name asc') {
      return left.title.localeCompare(right.title);
    }
    if (sortMode === 'Name desc') {
      return right.title.localeCompare(left.title);
    }
    if (sortMode === 'Size asc') {
      return left.fileSize - right.fileSize;
    }
    if (sortMode === 'Size desc') {
      return right.fileSize - left.fileSize;
    }
    if (sortMode === 'Time asc') {
      return left.time - right.time;
    }
    return right.time - left.time;
  });
}

export function nextDownloadStatusFilter(current: string): string {
  const options: string[] = ['All'].concat(DOWNLOAD_STATUS_FILTER_OPTIONS);
  return nextStringOption(current, options);
}

export function nextDownloadLabelFilter(current: string, labels: DownloadLabel[]): string {
  const options: string[] = ['__all__', ''];
  for (let i = 0; i < labels.length; i++) {
    options.push(labels[i].label);
  }
  return nextStringOption(current, options);
}

export function nextDownloadSortMode(current: string): string {
  const options: string[] = ['Default', 'GID asc', 'GID desc', 'Time asc', 'Rating asc', 'Rating desc', 'Name asc', 'Name desc',
    'Size asc', 'Size desc'];
  return nextStringOption(current, options);
}

export function nextDownloadCategoryFilter(current: string): string {
  const options: string[] = ['All', 'Misc', 'Doujinshi', 'Manga', 'Artist CG', 'Game CG', 'Image Set', 'Cosplay',
    'Asian Porn', 'Non-H', 'Western', 'Unknown'];
  return nextStringOption(current, options);
}

export function nextStringOption(current: string, options: string[]): string {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === current) {
      return options[(i + 1) % options.length];
    }
  }
  return options.length > 0 ? options[0] : current;
}

export function nextDownloadLabel(current: string, labels: DownloadLabel[]): string {
  const options: string[] = [''];
  for (let i = 0; i < labels.length; i++) {
    options.push(labels[i].label);
  }
  for (let i = 0; i < options.length; i++) {
    if (options[i] === current) {
      return options[(i + 1) % options.length];
    }
  }
  return options.length > 1 ? options[1] : '';
}

export function downloadStateLabel(state: DownloadState): string {
  if (state === DownloadState.Wait) {
    return 'Waiting';
  }
  if (state === DownloadState.Downloading) {
    return 'Downloading';
  }
  if (state === DownloadState.Finish) {
    return 'Downloaded';
  }
  if (state === DownloadState.Failed) {
    return 'Failed';
  }
  if (state === DownloadState.Update) {
    return 'Updating';
  }
  if (state === DownloadState.Invalid) {
    return 'Invalid';
  }
  return 'Idle';
}

export function downloadStateColor(state: DownloadState): string {
  if (state === DownloadState.Wait) {
    return paletteDownloadStateWaitColor();
  }
  if (state === DownloadState.Downloading) {
    return paletteDownloadStateActiveColor();
  }
  if (state === DownloadState.Finish) {
    return paletteDownloadStateDoneColor();
  }
  if (state === DownloadState.Failed || state === DownloadState.Invalid) {
    return paletteDownloadStateFailedColor();
  }
  return paletteDownloadStateIdleColor();
}

export function currentThemeName(): string {
  return themeCurrentThemeName();
}

export function currentDarkModeThemeName(): string {
  return themeCurrentDarkModeThemeName();
}

export function isDarkTheme(): boolean {
  return themeIsDarkTheme();
}

export function isBlackTheme(): boolean {
  return themeIsBlackTheme();
}

export function themePageBackground(): string {
  return palettePageBackground();
}

export function themePrimaryColor(): string {
  return palettePrimaryColor();
}

export function themeSurface(): string {
  return paletteSurface();
}

export function themeSurfaceVariant(): string {
  return paletteSurfaceVariant();
}

export function themeFieldBackground(): string {
  return paletteFieldBackground();
}

export function themePrimaryText(): string {
  return palettePrimaryText();
}

export function themeSecondaryText(): string {
  return paletteSecondaryText();
}

export function themeTertiaryText(): string {
  return paletteTertiaryText();
}

export function themeMutedText(): string {
  return paletteMutedText();
}

export function themeDividerColor(): string {
  return paletteDividerColor();
}

export function themePlaceholderColor(): string {
  return palettePlaceholderColor();
}

export function themeSelectedBackground(): string {
  return paletteSelectedBackground();
}

export function themeSelectedBackgroundLight(): string {
  return paletteSelectedBackgroundLight();
}

function clampColorChannel(value: number): number {
  return Math.max(0, Math.min(255, Math.round(value)));
}

function hexChannel(value: number): string {
  const hex = clampColorChannel(value).toString(16).toUpperCase();
  return hex.length === 1 ? '0' + hex : hex;
}

function parseHexChannel(color: string, start: number): number {
  const parsed = Number.parseInt(color.substring(start, start + 2), 16);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function mixHexColor(from: string, to: string, amount: number): string {
  const source = from.length >= 7 && from.charAt(0) === '#' ? from : palettePrimaryColor();
  const target = to.length >= 7 && to.charAt(0) === '#' ? to : '#FFFFFF';
  const ratio = Math.max(0, Math.min(1, amount));
  const r = parseHexChannel(source, 1) + (parseHexChannel(target, 1) - parseHexChannel(source, 1)) * ratio;
  const g = parseHexChannel(source, 3) + (parseHexChannel(target, 3) - parseHexChannel(source, 3)) * ratio;
  const b = parseHexChannel(source, 5) + (parseHexChannel(target, 5) - parseHexChannel(source, 5)) * ratio;
  return '#' + hexChannel(r) + hexChannel(g) + hexChannel(b);
}

export function themeSurfaceColor(amount: number = 0.88): string {
  return mixHexColor(palettePrimaryColor(), '#FFFFFF', amount);
}

export function immersiveChromeHeightFromOffset(offsetY: number, expandedHeight: number): number {
  return Math.max(0, Math.min(expandedHeight, expandedHeight + offsetY));
}

function immersiveChromeOffsetFromHeight(height: number, expandedHeight: number): number {
  return Math.max(-expandedHeight, Math.min(0, height - expandedHeight));
}

function nextImmersiveChromeHeight(currentHeight: number, scrollOffset: number, contentOffset: number,
  expandedHeight: number): number {
  if (contentOffset <= 4) {
    return expandedHeight;
  }
  if (scrollOffset > 0) {
    return Math.max(0, currentHeight - scrollOffset);
  }
  return Math.max(0, Math.min(expandedHeight, currentHeight));
}

export function nextFloatingToolbarOffset(currentOffset: number, scrollOffset: number, contentOffset: number,
  barHeight: number): number {
  const currentHeight = immersiveChromeHeightFromOffset(currentOffset, barHeight);
  const nextHeight = nextImmersiveChromeHeight(currentHeight, scrollOffset, contentOffset, barHeight);
  return immersiveChromeOffsetFromHeight(nextHeight, barHeight);
}

export function downloadProgressText(item: DownloadInfo): string {
  const total = item.total > 0 ? item.total : item.pages;
  if (total <= 0) {
    return '-';
  }
  return item.finished.toString() + '/' + total.toString();
}

export function downloadSizeText(size: number): string {
  if (size <= 0) {
    return '0 B';
  }
  if (size < 1024) {
    return size.toString() + ' B';
  }
  if (size < 1024 * 1024) {
    return Math.round(size / 1024).toString() + ' KB';
  }
  return Math.round(size / 1024 / 1024).toString() + ' MB';
}

function currentReaderCacheSizeText(): string {
  const context = getAbilityContext();
  if (context === undefined) {
    return '0 B';
  }
  return downloadSizeText(readerImageCache.size(context).bytes);
}

function currentDownloadRedundancyText(): string {
  const context = getAbilityContext();
  if (context === undefined) {
    return '0 B';
  }
  const items = ehDownloadStore.getItems();
  const keepGids: number[] = [];
  for (let i = 0; i < items.length; i++) {
    keepGids.push(items[i].gid);
  }
  try {
    return downloadSizeText(ehDownloadFileStore.scanRedundantDirectories(context, keepGids).bytes);
  } catch (error) {
    return '0 B';
  }
}

export function downloadImageUrlForPage(page: GalleryPage): string {
  if (ehSettingsStore.getValue('download_origin_image', 'Off') === 'On' && page.originImageUrl.length > 0) {
    return page.originImageUrl;
  }
  return page.imageUrl;
}

export function downloadThreadLimit(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('download_thread', '5'));
  if (Number.isNaN(value) || value <= 0) {
    return 1;
  }
  return Math.max(1, Math.min(value, 10));
}

export function downloadPageIndexes(count: number): number[] {
  const indexes: number[] = [];
  if (ehSettingsStore.getValue('download_order_asc', 'On') === 'On') {
    for (let i = 0; i < count; i++) {
      indexes.push(i);
    }
  } else {
    for (let i = count - 1; i >= 0; i--) {
      indexes.push(i);
    }
  }
  return indexes;
}

export function downloadQueueSummary(items: DownloadInfo[]): string {
  let wait = 0;
  let active = 0;
  let failed = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].state === DownloadState.Wait) {
      wait++;
    } else if (items[i].state === DownloadState.Downloading) {
      active++;
    } else if (items[i].state === DownloadState.Failed) {
      failed++;
    }
  }
  if (active <= 0 && failed <= 0) {
    return '';
  }
  return uiText('Waiting') + ' ' + wait.toString() + ' / ' + uiText('Downloading') + ' ' + active.toString() +
    ' / ' + uiText('Failed') + ' ' + failed.toString();
}

export function routeTitle(route: GalleryRoute): string {
  for (let i = 0; i < DRAWER_ITEMS.length; i++) {
    if (DRAWER_ITEMS[i].route === route) {
      return DRAWER_ITEMS[i].title;
    }
  }
  return 'EhViewer';
}

export function routeSubtitle(route: GalleryRoute): string {
  for (let i = 0; i < DRAWER_ITEMS.length; i++) {
    if (DRAWER_ITEMS[i].route === route) {
      return DRAWER_ITEMS[i].subtitle;
    }
  }
  return '';
}

export function launchRouteFromSetting(value: string): GalleryRoute {
  if (value === 'Subscription') {
    return GalleryRoute.Subscription;
  }
  if (value === 'What\'s Hot') {
    return GalleryRoute.WhatsHot;
  }
  if (value === 'Favorites') {
    return GalleryRoute.Favorites;
  }
  return GalleryRoute.Home;
}

export function settingsPanelTitle(panel: SettingsPanel): string {
  for (let i = 0; i < SETTINGS_HEADERS.length; i++) {
    if (SETTINGS_HEADERS[i].panel === panel) {
      return SETTINGS_HEADERS[i].title;
    }
  }
  if (panel === SettingsPanel.Session) {
    return 'Sign in';
  }
  if (panel === SettingsPanel.MyTags) {
    return 'My Tags';
  }
  if (panel === SettingsPanel.TranslationPrompt) {
    return 'System prompts';
  }
  if (panel === SettingsPanel.ReaderPresets) {
    return 'Reading presets';
  }
  if (panel === SettingsPanel.CommentBlacklist) {
    return 'Comment blacklist';
  }
  if (panel === SettingsPanel.RemoteStorage) {
    return 'Remote storage';
  }
  return 'Settings';
}

export function settingsRowsForPanel(panel: SettingsPanel, themeName: string, entries: SettingEntry[]): SettingsRowItem[] {
  if (panel === SettingsPanel.Eh) {
    const followSystemDarkMode = settingEntryValue(entries, 'follow_system_dark_mode', 'Off') === 'On';
    const listMode = settingEntryValue(entries, 'list_mode', 'Detail');
    const rows: SettingsRowItem[] = [
      staticSettingsRow('identity_cookie', 'Identity cookies',
        'View or import identity cookies; local igneous is never exported or transferred', '', 'navigation'),
      optionSettingsRow('gallery_site', 'Gallery site', 'Select E-Hentai or ExHentai for browsing and requests', entries, ['E-Hentai', 'ExHentai']),
      staticSettingsRow('u_config', 'UConfig', 'Account configuration page, requires sign in', '', 'navigation'),
      optionSettingsRow('use_account_default_filter', 'Use account filters', 'Use filtering options captured from UConfig', entries, ON_OFF_OPTIONS),
      staticSettingsRow('my_tags', 'My Tags', 'Manage watched and hidden tags, requires sign in', '', 'navigation'),
      optionSettingsRow('launch_page', 'Launch page', 'Default start scene after warnings and sign-in checks', entries, ['Homepage', 'Subscription', 'What\'s Hot', 'Favorites']),
      optionSettingsRow('list_mode', 'List mode', 'Choose detail, thumbnail or extended gallery cards', entries, ['Detail', 'Thumb', 'Extended'])
    ];
    if (listMode === 'Thumb') {
      rows.push(optionSettingsRow('thumb_size', 'Thumb size', 'Thumbnail column size in thumbnail mode', entries,
        ['Small', 'Medium', 'Large', 'XLarge']));
      rows.push(optionSettingsRow('show_gallery_rating', 'Show gallery rating',
        'Display rating in thumbnail cards', entries, ON_OFF_OPTIONS));
      rows.push(optionSettingsRow('show_gallery_language', 'Show gallery language',
        'Display language in thumbnail cards', entries, ON_OFF_OPTIONS));
    } else {
      rows.push(optionSettingsRow('detail_size', 'Detail size', 'Gallery card size in detail and extended modes', entries,
        ['Compact', 'Medium', 'Loose']));
    }
    rows.push(
      optionSettingsRow(HISTORY_INFO_SIZE_KEY, 'History size', 'Maximum stored gallery history records',
        entries, historyInfoSizeOptions()),
      optionSettingsRow('show_jpn_title', 'Show Japanese title', 'Prefer original title when available', entries, ON_OFF_OPTIONS),
      optionSettingsRow('show_gallery_pages', 'Show gallery pages', 'Display page count in gallery list rows', entries, ON_OFF_OPTIONS),
      optionSettingsRow('show_tag_translations', 'Show tag translations', 'Use translated tag labels when data is available', entries, ON_OFF_OPTIONS),
      optionSettingsRow('split_screen_mode', 'Split screen mode', 'Use left-right panes on wide screens', entries, ON_OFF_OPTIONS),
      optionSettingsRow('follow_system_dark_mode', 'Follow system dark mode', 'Use Light in system light mode and the selected dark theme in system dark mode', entries, ON_OFF_OPTIONS),
      optionSettingsRow('theme',
        followSystemDarkMode ? 'Dark mode theme' : 'Theme',
        followSystemDarkMode ? 'Choose Dark or Black when the system enters dark mode' :
          'Choose Light, Dark or Black for the app interface',
        entries, followSystemDarkMode ? ['Dark', 'Black'] : ['Light', 'Dark', 'Black']),
      optionSettingsRow('theme_color', 'Theme color',
        'Choose the accent color used by app bars, buttons and selected items', entries,
        ['Blue', 'Sky Blue', 'Teal', 'Green', 'Purple', 'Orange', 'Rose']),
      optionSettingsRow('ui_style', 'Interface style',
        'Choose the base layout or the Harmony native material style', entries,
        ['Classic', 'Harmony']),
      optionSettingsRow(FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, 'Smart grip',
        'Move floating action buttons to the detected holding hand', entries, ON_OFF_OPTIONS),
      staticSettingsRow('filter', 'Filter', 'Keyword/gallery filtering rules', '', 'navigation'),
      staticSettingsRow('comment_blacklist', 'Comment blacklist',
        'Block comments from selected user names', '', 'navigation'),
      optionSettingsRow('show_eh_events', 'Automatic check-in',
        'Visit E-Hentai on app startup to claim the daily account reward', entries, ON_OFF_OPTIONS),
      optionSettingsRow('show_eh_limits', 'Show EH limits', 'Display account and image limits in the drawer', entries, ON_OFF_OPTIONS),
      optionSettingsRow('cellular_network_warning', 'Cellular network warning', 'Warn before network-heavy operations on mobile data', entries, ON_OFF_OPTIONS)
    );
    return rows;
  }

  if (panel === SettingsPanel.Read) {
    const readingDirection = normalizeReadingDirectionOption(settingEntryValue(entries, 'reading_direction', 'Right to left'));
    const continuousMode = readingDirection === 'Top to bottom';
    const adaptiveDualPage = settingEntryValue(entries, 'adaptive_dual_page', 'Off') === 'On';
    const rows: SettingsRowItem[] = [
      staticSettingsRow('reader_presets', 'Reading presets',
        'Save and quickly apply groups of reader settings', '', 'navigation'),
      optionSettingsRow('screen_rotation', 'Screen rotation', 'Reader orientation policy', entries,
        continuousMode || adaptiveDualPage ? ['Default', 'Portrait', 'Landscape', 'Auto rotate'] :
          ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image']),
      optionSettingsRow('reading_direction', 'Reading direction', 'Left-to-right, right-to-left or vertical reader movement', entries,
        adaptiveDualPage ? ['Left to right', 'Right to left'] : ['Left to right', 'Right to left', 'Top to bottom']),
      optionSettingsRow('page_scaling', 'Page scaling', 'Choose how reader pages fit the screen', entries,
        adaptiveDualPage ? ['Fit screen'] : continuousMode ? ['Actual size', 'Fit width', 'Fixed scale'] :
          ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale']),
      optionSettingsRow('adaptive_dual_page', 'Adaptive dual page',
        'Show two wide or narrow pages together when both fit on screen', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_crop_white_borders', 'Crop white and black borders',
        'Automatically trim uniform light or dark margins while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_moire_reduction', 'Moiré reduction',
        'Reduce screentone interference patterns while scaling reader pages', entries,
        ['Off', 'Auto', 'Low', 'Medium', 'High']),
      optionSettingsRow('reader_image_super_resolution', 'Image super resolution',
        'Use the system image engine to enhance low-resolution reader pages', entries, ON_OFF_OPTIONS)
    ];
    const superResolutionEngines = readerSuperResolutionEngineOptions();
    if (settingEntryValue(entries, 'reader_image_super_resolution', 'Off') === 'On' &&
      superResolutionEngines.length > 1) {
      rows.push(optionSettingsRow('reader_super_resolution_engine', 'Super-resolution engine',
        'Choose detail enhancement or Core Vision AI on API 26 devices', entries, superResolutionEngines));
    }
    rows.push(
      optionSettingsRow('reader_sdr_to_hdr', 'SDR to HDR',
        'Convert reader images in the prerender range to HDR; super resolution runs first when both are enabled',
        entries, ON_OFF_OPTIONS),
      optionSettingsRow('start_position', 'Start position', 'Where a gallery starts when opened', entries, ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center']),
      optionSettingsRow('start_transfer_time', 'Auto transfer time', 'Delay before automatically advancing to the next page', entries, readerAutoTransferTimeOptions()),
      optionSettingsRow('reader_standalone', 'Standalone reader', 'Open reader in a standalone ability', entries, ON_OFF_OPTIONS),
      optionSettingsRow(MULTI_DEVICE_CONTINUATION_SETTING_KEY, 'Multi-device continuation',
        'Open the current comic page on another device', entries, ON_OFF_OPTIONS),
      optionSettingsRow('keep_screen_on', 'Keep screen on', 'Prevent screen sleep while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_clock', 'Show clock', 'Show clock overlay in the reader', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_progress', 'Show progress', 'Show reader progress overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_battery', 'Show battery', 'Show battery overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('volume_page', 'Volume page', 'Use volume buttons to turn pages', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reverse_volume_page', 'Reverse volume buttons',
        'Swap the page-turning direction of volume up and volume down', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reading_fullscreen', 'Reading fullscreen', 'Hide system chrome while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_background', 'Reader background', 'Background color behind reader pages', entries, ['Black', 'White', 'Deep gray']),
      optionSettingsRow('custom_screen_lightness', 'Custom brightness', 'Enable custom reader brightness', entries, ON_OFF_OPTIONS),
      optionSettingsRow('screen_lightness', 'Screen lightness', 'Custom reader brightness when enabled', entries, readerBrightnessLevelOptions()),
      optionSettingsRow('ultra_dark_mode', 'Ultra dark mode', 'Dim reader with a black overlay and minimum system brightness', entries, ON_OFF_OPTIONS),
      optionSettingsRow('ultra_dark_lightness', 'Ultra dark brightness', 'Black overlay opacity while ultra dark mode is enabled', entries, readerUltraDarkLightnessOptions())
    );
    return rows;
  }

  if (panel === SettingsPanel.Download) {
    return [
      optionSettingsRow('download_location', 'Download location',
        'App files, public Downloads, or a configured remote storage server',
        entries, ['App files', 'Downloads', 'Remote server']),
      staticSettingsRow('remote_storage', 'Remote storage',
        'WebDAV profiles for backup, sync and download mirror', '', 'navigation'),
      optionSettingsRow('download_thread', 'Multi-thread download', 'Number of images downloaded at the same time',
        entries, ['1', '2', '3', '4', '5', '8', '10']),
      optionSettingsRow('preload_image', 'Preload image', 'Number of following reader images loaded in advance',
        entries, ['0', '3', '5', '10', '20']),
      optionSettingsRow('download_list_pagination', 'Download list pagination', 'Paginate large download lists', entries, ON_OFF_OPTIONS),
      optionSettingsRow('image_size', 'Image resolution', 'Requested E-Hentai image size', entries,
        ['Auto', '780x', '1280x', '1600x', '2400x', 'Original']),
      optionSettingsRow('download_origin_image', 'Download original image', 'Prefer original files when available', entries, ON_OFF_OPTIONS),
      optionSettingsRow('download_timeout', 'Download timeout', 'Network timeout for image tasks', entries, ['15s', '30s', '60s']),
      optionSettingsRow('download_order_asc', 'Download order ascending', 'Store pages in ascending page order', entries, ON_OFF_OPTIONS),
      staticSettingsRow('restore_download_items', 'Restore download items', 'Rebuild queue from downloaded folders', 'Run', 'action'),
      staticSettingsRow('clean_redundancy', 'Clean redundancy',
        'Delete downloaded gallery folders that are no longer in the download list',
        currentDownloadRedundancyText(), 'action')
    ];
  }

  if (panel === SettingsPanel.Privacy) {
    return [
      optionSettingsRow('pattern_protection', 'Identity authentication', 'Verify identity when the app returns from background',
        entries, identityAuthenticationOptions()),
      optionSettingsRow('enable_secure', 'Privacy mode', 'Prevent screenshots and insecure previews', entries, ON_OFF_OPTIONS),
      optionSettingsRow('save_parse_error_body', 'Save parse error body', 'Persist parser failures for debugging', entries, ON_OFF_OPTIONS),
      optionSettingsRow('save_crash_log', 'Save crash log', 'Persist app errors and debug messages locally', entries, ON_OFF_OPTIONS),
      staticSettingsRow('clear_app_log', 'Clear saved log', 'Delete the local app log file', 'Clear', 'action')
    ];
  }

  if (panel === SettingsPanel.Translation) {
    const machineProvider = settingEntryValue(entries, 'translation_machine_provider', 'Google Web');
    const aiEnabled = settingEntryValue(entries, 'translation_ai_enabled', 'Off') === 'On';
    const aiProvider = settingEntryValue(entries, 'translation_ai_provider', 'DeepSeek');
    const machineProviderOptions = ['Google Web', 'Bing Web', 'Baidu Web', 'Youdao Web', 'MyMemory', 'Lingva'];
    const machineProviderDescriptions = [
      'Free Google web translation without an API key',
      'Free Microsoft web translation without an API key',
      'Free Baidu web translation without an API key',
      'Free Youdao web translation without an API key',
      'Public translation memory with a short text limit',
      'Open-source Google translation proxy'
    ];
    const aiProviderOptions = ['DeepSeek', 'OpenAI', 'Gemini', 'Custom API'];
    const aiProviderDescriptions = [
      'DeepSeek AI translation using your API key',
      'OpenAI model translation using your API key',
      'Google Gemini translation using your API key',
      'Saved OpenAI-compatible APIs and local model services'
    ];
    const rows: SettingsRowItem[] = [
      optionSettingsRow('translation_buttons_enabled', 'Translation feature',
        'Show translation buttons on gallery lists, details and comments', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_translation_enabled', 'Comic translation',
        'Show a draggable translation button in the reader', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_ocr_debug_log', 'Record comic OCR debug data',
        'Save OCR lines, estimated font sizes, grouping and overlay coordinates locally', entries, ON_OFF_OPTIONS),
      staticSettingsRow('reader_ocr_debug_export', 'Export comic OCR debug data',
        'Export recorded OCR and overlay layout data to public Downloads', 'Export', 'action'),
      optionSettingsRow('translation_ai_enabled', 'AI translation',
        'Use the selected AI service instead of ordinary machine translation', entries, ON_OFF_OPTIONS),
      optionSettingsRow('translation_target_language', 'Target language',
        'Language used for gallery titles and comments', entries,
        ['Simplified Chinese', 'Traditional Chinese', 'English', 'Japanese', 'Korean']),
      optionSettingsRow('translation_timeout', 'Translation timeout',
        'Maximum wait time for a translation request', entries, ['10s', '15s', '20s', '30s', '45s', '60s'])
    ];
    if (!aiEnabled) {
      rows.push(staticSettingsRow('translation_machine_section', 'Machine translation',
        'Choose the web translation service', '', 'section'));
      rows.push(optionSettingsRow('translation_machine_provider', 'Machine translation provider',
        'Choose the web translation service', entries, machineProviderOptions, machineProviderDescriptions));
    } else {
      rows.push(staticSettingsRow('translation_ai_section', 'AI translation service',
        'Choose the AI translation service', '', 'section'));
      rows.push(optionSettingsRow('translation_ai_provider', 'AI translation provider',
        'Choose the AI service used while AI translation is enabled', entries, aiProviderOptions, aiProviderDescriptions));
      rows.push(optionSettingsRow('translation_ai_thinking_enabled', 'Thinking mode',
        'Let supported AI models reason before translating; disabling uses non-thinking or the lowest available level',
        entries, ON_OFF_OPTIONS));
      rows.push(optionSettingsRow('translation_ai_conversation_log', 'Record AI conversations',
        'Save prompts sent to AI services and their returned text locally; disabling clears all records', entries,
        ON_OFF_OPTIONS));
      rows.push(staticSettingsRow('translation_ai_log_export', 'Export AI conversation records',
        'Export recorded AI translation conversations to public Downloads', 'Export', 'action'));
    }
    rows.push(optionSettingsRow('translation_batch_enabled', 'Merge translation requests',
      'Combine pending texts into fewer requests; AI batches contain up to 5 texts', entries, ON_OFF_OPTIONS));
    if (!aiEnabled) {
      rows.push(staticSettingsRow('translation_public_notice', 'Public translation notice',
        'Public providers require no token but may be rate-limited or unavailable; translated text is sent to the selected service',
        machineProvider === 'Google Web' ? 'Experimental' : 'Public service', 'info'));
    }
    if (aiEnabled && aiProvider === 'DeepSeek') {
      rows.push(textSettingsRow('translation_deepseek_api_key', 'DeepSeek API key',
        'Stored locally and sent only to DeepSeek', entries, ''));
      rows.push(modelSettingsRow('translation_deepseek_model', 'DeepSeek model',
        'Fetch available models or enter a model name', settingEntryValue(entries, 'translation_deepseek_model',
          'deepseek-v4-flash')));
    } else if (aiEnabled && aiProvider === 'OpenAI') {
      rows.push(textSettingsRow('translation_official_openai_api_key', 'OpenAI API key',
        'Stored locally and sent only to OpenAI', entries, ''));
      rows.push(modelSettingsRow('translation_official_openai_model', 'OpenAI model',
        'Fetch available OpenAI models or enter a model name',
        settingEntryValue(entries, 'translation_official_openai_model', 'gpt-4.1-mini')));
    } else if (aiEnabled && aiProvider === 'Gemini') {
      rows.push(textSettingsRow('translation_gemini_api_key', 'Gemini API key',
        'Stored locally and sent only to Google Gemini', entries, ''));
      rows.push(modelSettingsRow('translation_gemini_model', 'Gemini model',
        'Fetch available Gemini models or enter a model name',
        settingEntryValue(entries, 'translation_gemini_model', 'gemini-3.5-flash')));
    } else if (aiEnabled && aiProvider === 'Custom API') {
      const savedApis = parseSavedTranslationApis(settingEntryValue(entries, 'translation_custom_apis', '[]'));
      const selectedName = settingEntryValue(entries, 'translation_custom_api_selected', '');
      const selected = findSavedTranslationApi(savedApis, selectedName);
      const apiNames: string[] = [];
      for (let i = 0; i < savedApis.length; i++) {
        apiNames.push(savedApis[i].name);
      }
      apiNames.push('New...');
      rows.push(optionSettingsRow('translation_custom_api_selected', 'Saved API',
        'Choose a saved API or create a new configuration', entries, apiNames));
      if (selected !== null) {
        rows.push(valueSettingsInputRow('translation_custom_api_name', 'API name',
          'Name shown in the saved API list', selected.name));
        rows.push(valueSettingsInputRow('translation_custom_api_base_url', 'API address',
          'Base URL ending in /v1 or a complete chat completions URL', selected.baseUrl));
        rows.push(valueSettingsInputRow('translation_custom_api_key', 'API key',
          'Stored separately for this saved API', selected.apiKey));
        rows.push(modelSettingsRow('translation_custom_api_model', 'Model',
          'Fetch models from this API or enter a model name', selected.model));
      }
    }
    if (aiEnabled) {
      rows.push(staticSettingsRow('translation_prompt_settings', 'System prompts',
        'Choose, edit and save prompts used by AI translation', '', 'navigation'));
    }
    rows.push(staticSettingsRow('translation_test', 'Test translation',
      'Translate a short sample with the current provider', 'Run', 'action'));
    return rows;
  }

  if (panel === SettingsPanel.Advanced) {
    const rows: SettingsRowItem[] = [
      staticSettingsRow('dump_logcat', 'Export log', 'Save the local app log to a text file', 'Export', 'action'),
      staticSettingsRow('clear_download_path_cache', 'Clear download path cache', 'Refresh cached file path and size lookups', 'Run', 'action'),
      staticSettingsRow('clear_memory_cache', 'Clear cache', 'Drop reader image and page caches',
        currentReaderCacheSizeText(), 'action'),
      optionSettingsRow('read_cache_size', 'Read cache size', 'Reader cache budget', entries,
        ['160 MB', '320 MB', '640 MB', '1 GB', '2 GB']),
      optionSettingsRow('app_language', 'App language', 'Language override', entries,
        ['System', 'English', 'zh-CN', 'zh-TW']),
      staticSettingsRow('proxy_settings', 'Proxy',
        'Configure direct, system, HTTP or SOCKS5 proxy', settingEntryValue(entries, 'proxy', 'System'), 'dialog'),
      staticSettingsRow('network_diagnostics', 'Network diagnostics', 'Test E, EX, forums and repo connectivity with current settings', 'Run', 'action'),
    ];
    rows.push(optionSettingsRow('built_in_hosts', 'Built-in hosts', 'Force bundled host overrides; leave Off for normal Cloudflare DNS', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('built_ex_hosts', 'Built EX hosts', 'Force bundled ExHentai host overrides; leave Off unless your network needs them', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('dns_over_https', 'Secure DNS (DoH)', 'Encrypt DNS queries and reduce DNS pollution',
      entries, ON_OFF_OPTIONS));
    if (settingEntryValue(entries, 'dns_over_https', 'Off') === 'On') {
      rows.push(optionSettingsRow('dns_over_https_provider', 'DoH provider',
        'Select a certificate-validated RFC 8484 resolver', entries, ['Yandex', 'Cloudflare', 'Google']));
    }
    rows.push(optionSettingsRow('domain_fronting', 'Domain fronting', 'Bypass SNI blocking using built-in host fronting', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('auto_direct_connection', 'Direct connection check', 'Use direct connection when the selected site responds within 5s', entries, ON_OFF_OPTIONS));
    rows.push(staticSettingsRow('export_data', 'Export data',
      'Save settings, login cookies, gallery and search history, reading progress, favorites, downloads, browsing positions, filters and comment blacklist without igneous to a JSON file',
      'Export', 'action'));
    rows.push(staticSettingsRow('import_data', 'Import data', 'Restore settings and local data from a supported backup file', 'Import', 'action'));
    rows.push(staticSettingsRow('wifi_transfer', 'Wi-Fi Direct transfer',
      'Transfer application settings, reading progress, bookmarks, local favorites, comment blacklist, downloads and image files directly between nearby devices', '',
      'navigation'));
    return rows;
  }

  if (panel === SettingsPanel.About) {
    return [
      staticSettingsRow('declaration', 'Declaration', 'Current HarmonyOS repository', 'Info', 'message'),
      staticSettingsRow('author', 'Author', EH_AUTHOR_NAME, 'GitHub', 'url'),
      staticSettingsRow('latest_release', 'Version', 'Open the latest project release', EH_RELEASE_TAG, 'url'),
      staticSettingsRow('issue_help', 'Issue help', 'Open the project issue tracker', 'Issues', 'url'),
      staticSettingsRow('license', 'License', 'Open-source license used by this project', 'GPL-3.0', 'url'),
      staticSettingsRow('check_for_updates', 'Check for updates', 'Check the latest GitHub release', 'Run', 'action'),
      staticSettingsRow('update_tag_translation_database', 'Update tag translation database',
        'Check for and download the latest Chinese tag translations', 'Run', 'action'),
      optionSettingsRow('close_auto_updates', 'Close automatic updates', 'Disable startup update check', entries, ON_OFF_OPTIONS),
      staticSettingsRow('donate', 'Donate', 'Support project development', 'Unavailable', 'url')
    ];
  }

  return [staticSettingsRow('theme', 'Theme', 'Choose the app interface theme', themeName, 'list')];
}

const ON_OFF_OPTIONS: string[] = ['On', 'Off'];

function readerAutoTransferTimeOptions(): string[] {
  const options: string[] = [];
  for (let i = 1; i <= 20; i++) {
    options.push(i.toString() + 's');
  }
  return options;
}

function readerBrightnessLevelOptions(): string[] {
  const options: string[] = [];
  for (let i = 0; i <= 100; i++) {
    options.push(i.toString() + '%');
  }
  return options;
}

export function readerUltraDarkLightnessOptions(): string[] {
  const options: string[] = [];
  for (let i = 1; i <= 100; i++) {
    options.push(i.toString() + '%');
  }
  return options;
}

export function identityAuthenticationOptions(): string[] {
  return [
    IDENTITY_AUTH_OFF,
    IDENTITY_AUTH_FINGERPRINT_FIRST,
    IDENTITY_AUTH_FACE_FIRST,
    IDENTITY_AUTH_PASSWORD_FIRST
  ];
}

function optionSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], options: string[],
  optionDescriptions: string[] = []): SettingsRowItem {
  let rawValue = settingEntryValue(entries, key, options.length > 0 ? options[0] : '');
  if (key === 'theme' && options.length > 0 && options.indexOf(rawValue) < 0) {
    rawValue = options[0];
  }
  if (key === 'ui_style' && rawValue === 'HarmonyOS 7') {
    rawValue = 'Harmony';
  }
  const sliderRow = key === 'start_transfer_time' || key === 'screen_lightness' || key === 'ultra_dark_lightness';
  return {
    key: key,
    title: title,
    summary: summary,
    value: normalizeReaderSettingOption(key, rawValue),
    type: sliderRow ? 'slider' : options.length === 2 && options[0] === 'On' && options[1] === 'Off' ? 'switch' : 'list',
    options: options,
    optionDescriptions: optionDescriptions
  };
}

function normalizeScreenRotationOption(value: string): string {
  if (value === '1' || value === 'Portrait') {
    return 'Portrait';
  }
  if (value === '2' || value === 'Landscape') {
    return 'Landscape';
  }
  if (value === '3' || value === 'Sensor' || value === 'Auto rotate') {
    return 'Auto rotate';
  }
  if (value === '4' || value === 'Match image') {
    return 'Match image';
  }
  return 'Default';
}

export function normalizeReadingDirectionOption(value: string): string {
  if (value === '0' || value === 'Left to right') {
    return 'Left to right';
  }
  if (value === '2' || value === 'Top to bottom') {
    return 'Top to bottom';
  }
  return 'Right to left';
}

export function normalizePageScalingOption(value: string): string {
  if (value === '0' || value === 'Actual size' || value === 'Original') {
    return 'Actual size';
  }
  if (value === '1' || value === 'Fit width') {
    return 'Fit width';
  }
  if (value === '2' || value === 'Fit height') {
    return 'Fit height';
  }
  if (value === '4' || value === 'Fixed scale') {
    return 'Fixed scale';
  }
  return 'Fit screen';
}

export function normalizeStartPositionOption(value: string): string {
  if (value === '0' || value === 'Top left') {
    return 'Top left';
  }
  if (value === '2' || value === 'Bottom left') {
    return 'Bottom left';
  }
  if (value === '3' || value === 'Bottom right' || value === 'End') {
    return 'Bottom right';
  }
  if (value === '4' || value === 'Center') {
    return 'Center';
  }
  return 'Center';
}

function normalizeReaderSettingOption(key: string, value: string): string {
  if (key === 'screen_rotation') {
    return normalizeScreenRotationOption(value);
  }
  if (key === 'reading_direction') {
    return normalizeReadingDirectionOption(value);
  }
  if (key === 'page_scaling') {
    return normalizePageScalingOption(value);
  }
  if (key === 'start_position') {
    return normalizeStartPositionOption(value);
  }
  if (key === 'start_transfer_time') {
    return normalizeAutoTransferTimeOption(value);
  }
  if (key === 'screen_lightness') {
    return normalizeBrightnessLevelOption(value);
  }
  if (key === 'ultra_dark_lightness') {
    return normalizeUltraDarkLightnessOption(value);
  }
  if (key === 'pattern_protection') {
    return normalizeIdentityAuthenticationOption(value);
  }
  if (key === 'read_cache_size') {
    return normalizeReaderCacheSizeOption(value);
  }
  if (key === HISTORY_INFO_SIZE_KEY) {
    return normalizeHistoryInfoSizeOption(value);
  }
  return value;
}

export function normalizeReaderCacheSizeOption(value: string): string {
  if (value === '40 MB' || value === '80 MB') {
    return '160 MB';
  }
  if (value === '160 MB' || value === '320 MB' || value === '640 MB' || value === '1 GB' || value === '2 GB') {
    return value;
  }
  return '160 MB';
}

export function normalizeIdentityAuthenticationOption(value: string): string {
  if (value === 'On' || value === IDENTITY_AUTH_FINGERPRINT_FIRST) {
    return IDENTITY_AUTH_FINGERPRINT_FIRST;
  }
  if (value === IDENTITY_AUTH_FACE_FIRST) {
    return IDENTITY_AUTH_FACE_FIRST;
  }
  if (value === IDENTITY_AUTH_PASSWORD_FIRST) {
    return IDENTITY_AUTH_PASSWORD_FIRST;
  }
  return IDENTITY_AUTH_OFF;
}

export function normalizeAutoTransferTimeOption(value: string): string {
  const seconds = Number.parseInt(value);
  if (Number.isNaN(seconds)) {
    return '5s';
  }
  return Math.max(1, Math.min(20, seconds)).toString() + 's';
}

export function normalizeBrightnessLevelOption(value: string): string {
  const percent = Number.parseInt(value);
  if (Number.isNaN(percent)) {
    return '50%';
  }
  return Math.max(0, Math.min(100, percent)).toString() + '%';
}

export function normalizeUltraDarkLightnessOption(value: string): string {
  const percent = Number.parseInt(value);
  if (Number.isNaN(percent)) {
    return '50%';
  }
  return Math.max(1, Math.min(100, percent)).toString() + '%';
}

export function textSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], fallback: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: settingEntryValue(entries, key, fallback),
    type: 'input'
  };
}

function valueSettingsInputRow(key: string, title: string, summary: string, value: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: value,
    type: 'input'
  };
}

function modelSettingsRow(key: string, title: string, summary: string, value: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: value,
    type: 'model'
  };
}

export function staticSettingsRow(key: string, title: string, summary: string, value: string, type: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: value,
    type: type
  };
}

export function settingEntryValue(entries: SettingEntry[], key: string, fallback: string): string {
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].key === key) {
      return entries[i].value;
    }
  }
  return fallback;
}

export function cloneStringOptions(options: string[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < options.length; i++) {
    result.push(options[i]);
  }
  return result;
}

export function isValidProxyPortText(value: string): boolean {
  const port = Number.parseInt(value);
  return !Number.isNaN(port) && port > 0 && port <= 65535 && port.toString() === value.trim();
}

export function normalizeProxyOption(value: string): string {
  if (value === 'Off' || value === 'HTTP' || value === 'SOCKS') {
    return value;
  }
  return 'System';
}

export function isValidProxyHostText(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return true;
  }
  if (trimmed.length > 255) {
    return false;
  }
  return /^[A-Za-z0-9.\-_:]+$/.test(trimmed);
}

export function formatNetworkDiagnostics(results: NetworkDiagnosticResult[]): string {
  const parts: string[] = [];
  for (let i = 0; i < results.length; i++) {
    const item = results[i];
    const status = item.statusCode > 0 ? item.statusCode.toString() : 'ERR';
    parts.push(item.label + ' ' + status + ' ' + item.elapsedMs.toString() + 'ms' +
      (item.ok ? '' : ' ' + item.message));
  }
  return 'Network diagnostics: ' + parts.join(' | ');
}

export function listModeForRoute(route: GalleryRoute): ListMode {
  if (route === GalleryRoute.Subscription) {
    return ListMode.Subscription;
  }
  if (route === GalleryRoute.WhatsHot) {
    return ListMode.WhatsHot;
  }
  if (route === GalleryRoute.TopLists) {
    return ListMode.TopList;
  }
  return ListMode.Normal;
}

export function routeUsesKeyword(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription || route === GalleryRoute.Favorites;
}

export function usesGallerySearchToolbar(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription ||
    route === GalleryRoute.WhatsHot || route === GalleryRoute.Favorites;
}

export function usesEmbeddedToolbar(route: GalleryRoute): boolean {
  return usesGallerySearchToolbar(route) || route === GalleryRoute.TopLists || route === GalleryRoute.History ||
    route === GalleryRoute.Downloads || route === GalleryRoute.Settings || route === GalleryRoute.Session;
}

export function defaultKeywordForRoute(_route: GalleryRoute): string {
  return '';
}

export function gallerySearchTitle(route: GalleryRoute, keyword: string, filterActive: boolean): string {
  const trimmed = keyword.trim();
  if (trimmed.length > 0) {
    return filterActive ? 'Filter: ' + trimmed : trimmed;
  }
  if (route === GalleryRoute.Subscription) {
    return 'Subscription';
  }
  if (route === GalleryRoute.WhatsHot) {
    return 'What\'s Hot';
  }
  if (route === GalleryRoute.Favorites) {
    return 'Favourite';
  }
  return 'Homepage';
}

export function currentGallerySite(): GallerySite {
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
}

export function effectiveListSite(_route: GalleryRoute): GallerySite {
  return currentGallerySite();
}

function gallerySiteName(site: GallerySite): string {
  return site === GallerySite.Ex ? 'ExHentai' : 'E-Hentai';
}

export function galleryListFailureMessage(result: GalleryListLoadResult, site: GallerySite): string {
  if (result.statusCode >= 200 && result.statusCode < 300) {
    return 'No results';
  }
  const status = result.statusCode > 0 ? 'HTTP ' + result.statusCode.toString() + ', ' : '';
  const url = result.url.length > 0 ? ', ' + result.url : '';
  return 'Load failed: ' + gallerySiteName(site) + ', ' + status + result.message + url;
}

export function withGalleryListMessage(result: GalleryListLoadResult, message: string): GalleryListLoadResult {
  return {
    ok: result.ok,
    url: result.url,
    statusCode: result.statusCode,
    message: message,
    pages: result.pages,
    nextPage: result.nextPage,
    nextUrl: result.nextUrl,
    resultCount: result.resultCount,
    galleries: result.galleries
  };
}

export function readerPageReferer(detailUrl: string, previews: GalleryPreview[], index: number, site: GallerySite): string {
  if (index > 0 && index - 1 < previews.length && previews[index - 1].pageUrl.length > 0) {
    return previews[index - 1].pageUrl;
  }
  if (detailUrl.length > 0) {
    return detailUrl;
  }
  return EhUrl.getReferer(site);
}

export function readerDisplayImageUrl(page: GalleryPage, preferOriginal: boolean): string {
  if (preferOriginal && page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0 &&
    localImagePathExists(page.cachedOriginImagePath)) {
    return readerLocalImageSource(page.cachedOriginImagePath);
  }
  if (!preferOriginal && page.cachedImagePath !== undefined && page.cachedImagePath.length > 0 &&
    localImagePathExists(page.cachedImagePath)) {
    return readerLocalImageSource(page.cachedImagePath);
  }
  if (preferOriginal && page.originImageUrl.length > 0) {
    return '';
  }
  return '';
}

export function cacheReaderImageForPage(page: GalleryPage, onReady: (page: GalleryPage) => void,
  gallery?: GalleryInfo, index?: number, abilityContext?: common.UIAbilityContext,
  onError?: (message: string) => void, priority: number = IMAGE_DOWNLOAD_PRIORITY_READER,
  options?: ImageDownloadOptions): Promise<void> {
  const context = abilityContext !== undefined ? abilityContext : getAbilityContext();
  if (context === undefined) {
    if (onError !== undefined) {
      onError('Ability context is not ready');
    }
    return Promise.resolve();
  }

  if (gallery !== undefined && index !== undefined) {
    const downloadedPath = ehDownloadFileStore.findPageImage(context, gallery, index);
    if (downloadedPath.length > 0) {
      onReady(cloneGalleryPageWithCache(page, downloadedPath));
      return Promise.resolve();
    }
  }

  if (page.imageUrl.length === 0) {
    if (onError !== undefined) {
      onError('Image URL missing');
    }
    return Promise.resolve();
  }

  const existing = readerImageCache.getCachedPath(context, page.imageUrl, readerPageImageCacheKey(page, false));
  if (existing.length > 0) {
    onReady(cloneGalleryPageWithCache(page, existing));
    return Promise.resolve();
  }

  return readerImageCache.ensureCached(context, page.imageUrl, page.pageUrl, priority, undefined,
    readerPageImageCacheKey(page, false), options).then((path: string) => {
    if (path.length > 0) {
      onReady(cloneGalleryPageWithCache(page, path));
    } else if (onError !== undefined) {
      onError('Image cache path is empty');
    }
  }).catch((error: Error) => {
    if (onError !== undefined) {
      onError(error.message);
    }
  });
}

export function readerPageImageCacheKey(page: GalleryPage, original: boolean = false): string {
  if (page.pageUrl.length <= 0) {
    return '';
  }
  return page.pageUrl + (original ? '#origin' : '#image');
}

function enqueueThumbnailReady(path: string, onReady: (path: string) => void): void {
  THUMBNAIL_READY_QUEUE.push({ path: path, onReady: onReady });
  scheduleThumbnailReadyDelivery();
}

function scheduleThumbnailReadyDelivery(): void {
  if (thumbnailReadyScheduled) {
    return;
  }
  thumbnailReadyScheduled = true;
  setTimeout(() => {
    thumbnailReadyScheduled = false;
    const count = Math.min(THUMBNAIL_READY_BATCH_SIZE, THUMBNAIL_READY_QUEUE.length);
    const batch = THUMBNAIL_READY_QUEUE.splice(0, count);
    for (let i = 0; i < batch.length; i++) {
      try {
        batch[i].onReady(batch[i].path);
      } catch (error) {
      }
    }
    if (THUMBNAIL_READY_QUEUE.length > 0) {
      scheduleThumbnailReadyDelivery();
    }
  }, THUMBNAIL_READY_BATCH_DELAY_MS);
}

// 不传 onReady 时只预下载，不占用逐帧派发给卡片的图片更新队列。
export function cacheThumbnailImage(url: string, onReady?: (path: string) => void, onError?: () => void): void {
  const context = getAbilityContext();
  if (context === undefined || url.length === 0) {
    if (onError !== undefined) {
      onError();
    }
    return;
  }

  const existing = readerImageCache.getCachedPath(context, url);
  if (existing.length > 0) {
    if (onReady !== undefined) {
      enqueueThumbnailReady(existing, onReady);
    }
    return;
  }

  readerImageCache.ensureCached(context, url, EhUrl.getReferer(currentGallerySite()),
    IMAGE_DOWNLOAD_PRIORITY_BACKGROUND, undefined, '',
    { retryLimit: THUMBNAIL_RETRY_LIMIT }).then((path: string) => {
    if (path.length > 0) {
      if (onReady !== undefined) {
        enqueueThumbnailReady(path, onReady);
      }
    } else if (onError !== undefined) {
      onError();
    }
  }).catch(() => {
    if (onError !== undefined) {
      onError();
    }
  });
}

export function cachePreviewThumbnail(preview: GalleryPreview, onReady: (path: string) => void,
  onError?: () => void): void {
  const context = getAbilityContext();
  if (context === undefined || preview.imageUrl.length === 0) {
    if (onError !== undefined) {
      onError();
    }
    return;
  }

  const existing = previewThumbnailCache.getCroppedPath(context, preview);
  if (existing.length > 0) {
    enqueueThumbnailReady(existing, onReady);
    return;
  }

  previewThumbnailCache.ensureCropped(context, preview, EhUrl.getReferer(currentGallerySite())).then((path: string) => {
    if (path.length > 0) {
      enqueueThumbnailReady(path, onReady);
    } else if (onError !== undefined) {
      onError();
    }
  }).catch(() => {
    if (onError !== undefined) {
      onError();
    }
  });
}

function cloneGalleryPageWithCache(page: GalleryPage, cachedPath: string): GalleryPage {
  return {
    pageUrl: page.pageUrl,
    imageUrl: page.imageUrl,
    skipHathKey: page.skipHathKey,
    originImageUrl: page.originImageUrl,
    showKey: page.showKey,
    cachedImagePath: cachedPath,
    cachedOriginImagePath: page.cachedOriginImagePath
  };
}

export function readerLocalImageSource(path: string): string {
  if (path.indexOf('://') >= 0) {
    return path;
  }
  try {
    return fileUri.getUriFromPath(path);
  } catch (error) {
    return 'file://' + path;
  }
}

function localImagePathExists(path: string): boolean {
  const localPath = path.startsWith('file://') ? path.substring('file://'.length) : path;
  if (localPath.length === 0 || localPath.endsWith('.part')) {
    return false;
  }
  try {
    if (!fs.accessSync(localPath)) {
      return false;
    }
    return fs.statSync(localPath).size > 0;
  } catch (error) {
    return false;
  }
}

export function readerZoomSize(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

export function readerPreloadCount(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('preload_image', '5'));
  if (Number.isNaN(value) || value <= 0) {
    return 0;
  }
  return Math.min(value, 20);
}

export function categoryName(category: number): string {
  switch (category) {
    case GalleryCategory.Misc:
      return 'MISC';
    case GalleryCategory.Doujinshi:
      return 'DOUJINSHI';
    case GalleryCategory.Manga:
      return 'MANGA';
    case GalleryCategory.ArtistCg:
      return 'ARTIST CG';
    case GalleryCategory.GameCg:
      return 'GAME CG';
    case GalleryCategory.ImageSet:
      return 'IMAGE SET';
    case GalleryCategory.Cosplay:
      return 'COSPLAY';
    case GalleryCategory.AsianPorn:
      return 'ASIAN PORN';
    case GalleryCategory.NonH:
      return 'NON-H';
    case GalleryCategory.Western:
      return 'WESTERN';
    default:
      return 'UNKNOWN';
  }
}

export function categoryDisplayName(category: number): string {
  if (!shouldShowTagTranslations()) {
    return categoryName(category);
  }
  switch (category) {
    case GalleryCategory.Misc:
      return '杂项';
    case GalleryCategory.Doujinshi:
      return '同人志';
    case GalleryCategory.Manga:
      return '漫画';
    case GalleryCategory.ArtistCg:
      return '艺术家 CG';
    case GalleryCategory.GameCg:
      return '游戏 CG';
    case GalleryCategory.ImageSet:
      return '图集';
    case GalleryCategory.Cosplay:
      return '角色扮演';
    case GalleryCategory.AsianPorn:
      return '亚洲色情';
    case GalleryCategory.NonH:
      return '非 H';
    case GalleryCategory.Western:
      return '西方';
    default:
      return '未知';
  }
}

export function tagNamespaceDisplayName(namespace: string): string {
  const normalized = namespace.trim().toLowerCase();
  if (!shouldShowTagTranslations()) {
    return normalized;
  }
  switch (normalized) {
    case 'artist':
      return '艺术家';
    case 'group':
      return '社团';
    case 'parody':
      return '原作';
    case 'character':
      return '角色';
    case 'female':
      return '女性';
    case 'male':
      return '男性';
    case 'mixed':
      return '混合';
    case 'language':
      return '语言';
    case 'cosplayer':
      return '角色扮演者';
    case 'other':
      return '其他';
    case 'location':
      return '地点';
    case 'rows':
      return '行数';
    default:
      return normalized;
  }
}

export function tagTranslationOptionText(original: string, translated: string): string {
  return shouldShowTagTranslations() ? translated : original;
}

export function categoryColor(category: number): string {
  switch (category) {
    case GalleryCategory.Doujinshi:
      return '#B45F06';
    case GalleryCategory.Manga:
      return '#6A4FB3';
    case GalleryCategory.ArtistCg:
      return '#2F6F8F';
    case GalleryCategory.GameCg:
      return '#7A5A22';
    case GalleryCategory.ImageSet:
      return '#327A5B';
    case GalleryCategory.Cosplay:
      return '#A04462';
    case GalleryCategory.AsianPorn:
      return '#8A4F2B';
    case GalleryCategory.NonH:
      return '#4D6D8C';
    case GalleryCategory.Western:
      return '#556B2F';
    case GalleryCategory.Misc:
      return '#6B7280';
    default:
      return '#8A94A3';
  }
}

export function ratingText(rating: number): string {
  return rating < 0 ? '-' : rating.toString();
}

export function galleryDisplayTitle(gallery: GalleryInfo): string {
  if (ehSettingsStore.getValue('show_jpn_title', 'Off') === 'On' &&
    gallery.titleJpn !== undefined && gallery.titleJpn.length > 0) {
    return decodeHtmlEntities(gallery.titleJpn);
  }
  if (gallery.title.length > 0) {
    return decodeHtmlEntities(gallery.title);
  }
  if (gallery.titleJpn !== undefined && gallery.titleJpn.length > 0) {
    return decodeHtmlEntities(gallery.titleJpn);
  }
  return 'Untitled';
}

export function showGalleryPages(): boolean {
  return ehSettingsStore.getValue('show_gallery_pages', 'Off') === 'On';
}

export function showGalleryRating(): boolean {
  return ehSettingsStore.getValue('show_gallery_rating', 'On') === 'On';
}

export function showGalleryLanguage(): boolean {
  return ehSettingsStore.getValue('show_gallery_language', 'On') === 'On';
}

export function galleryListMode(): string {
  return ehSettingsStore.getValue('list_mode', 'Detail');
}

export function galleryThumbWidth(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Medium');
  if (value === 'Small') {
    return 70;
  }
  if (value === 'Large') {
    return 104;
  }
  if (value === 'XLarge') {
    return 124;
  }
  return 86;
}

export function galleryThumbnailPreferredColumnWidth(): number {
  const thumbnailWidth = galleryThumbWidth();
  if (thumbnailWidth <= 70) {
    return 132;
  }
  if (thumbnailWidth >= 124) {
    return 216;
  }
  if (thumbnailWidth >= 104) {
    return 184;
  }
  return 156;
}

export function galleryDetailCardThumbWidth(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  if (value === 'Compact') {
    return 70;
  }
  if (value === 'Large' || value === 'Loose') {
    return 104;
  }
  return 86;
}

export function galleryDetailCardBaseHeight(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  const largeLayout = value === 'Large' || value === 'Loose';
  if (value === 'Compact') {
    return 96;
  }
  if (largeLayout) {
    return 158;
  }
  return 124;
}

export function galleryDetailCardHeight(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  const largeLayout = value === 'Large' || value === 'Loose';
  const extendedHeight = galleryListMode() === 'Extended' ? (largeLayout ? 39 : 31) : 0;
  return galleryDetailCardBaseHeight() + extendedHeight;
}

export function galleryDetailCardPreferredWidth(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  if (value === 'Compact') {
    return 300;
  }
  if (value === 'Large' || value === 'Loose') {
    return 400;
  }
  return 340;
}

export function galleryDetailCardMinWidth(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  if (value === 'Compact') {
    return 260;
  }
  if (value === 'Large' || value === 'Loose') {
    return 340;
  }
  return 300;
}

export function readerShowProgress(): boolean {
  return ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
}

export function readerClockText(): string {
  const now = new Date();
  return padTimeNumber(now.getHours()) + ':' + padTimeNumber(now.getMinutes());
}

function padTimeNumber(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

export function sortedStringKey(values: string[]): string {
  return values.slice().sort().join('|');
}

export function toggleStringValue(values: string[], value: string): string[] {
  const next = values.slice();
  const index = next.indexOf(value);
  if (index >= 0) {
    next.splice(index, 1);
  } else {
    next.push(value);
  }
  return next;
}
