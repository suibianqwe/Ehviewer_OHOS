import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, GalleryTagInfo, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import {
  HISTORY_INFO_SIZE_KEY,
  ehSettingsStore,
  historyInfoSizeLimitFromValue,
  historyInfoSizeOptions,
  normalizeHistoryInfoSizeOption,
  SettingEntry
} from '../services/EhSettingsStore';
import { GalleryListLoadResult, NetworkDiagnosticResult } from '../services/EhHttpClient';
import { EhUrl, ListMode } from '../services/EhUrl';
import { readerImageCache } from '../services/ReaderImageCache';
import { previewThumbnailCache } from '../services/PreviewThumbnailCache';
import { FilterRule, ehFilterStore } from '../services/EhFilterStore';
import { LocalFavoriteBackupInfo } from '../services/EhLocalFavoritesStore';
import { SearchBookmarkBackupInfo } from '../services/EhBookmarkStore';
import { EH_AUTHOR_NAME, EH_RELEASE_TAG } from '../services/EhBuildInfo';
import { normalizeGalleryLanguageCode } from '../services/GalleryLanguageSupport';
import {
  EH_THEME_PRIMARY_COLOR,
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
  themeTertiaryText as paletteTertiaryText
} from './EhTheme';

export interface EhBackupBundle {
  version: number;
  exportedAt: string;
  cookies: string;
  settings: SettingEntry[];
  history: GalleryInfo[];
  downloadItems: DownloadInfo[];
  downloadLabels: DownloadLabel[];
  filterRules: FilterRule[];
  localFavorites?: LocalFavoriteBackupInfo[];
  bookmarks?: SearchBookmarkBackupInfo[];
}

export const LANGUAGE_REVISION_KEY: string = 'ehviewer_language_revision';
export const THEME_REVISION_KEY: string = 'ehviewer_theme_revision';
export const HISTORY_READ_REVISION_KEY: string = 'ehviewer_history_read_revision';
export const GALLERY_TITLE_REVISION_KEY: string = 'ehviewer_gallery_title_revision';
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
  Advanced = 'advanced',
  About = 'about',
  Session = 'session',
  WebView = 'webview',
  Filter = 'filter',
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
  { panel: SettingsPanel.Advanced, title: 'Advanced', icon: 'A', summary: 'Network, cache, hosts and diagnostics' },
  { panel: SettingsPanel.About, title: 'About', icon: 'I', summary: 'Version and license' }
];

export function notifyLanguageChanged(): void {
  const current = AppStorage.get<number>(LANGUAGE_REVISION_KEY);
  AppStorage.setOrCreate<number>(LANGUAGE_REVISION_KEY, current === undefined ? 1 : current + 1);
}

export function notifyThemeChanged(): void {
  const current = AppStorage.get<number>(THEME_REVISION_KEY);
  AppStorage.setOrCreate<number>(THEME_REVISION_KEY, current === undefined ? 1 : current + 1);
  notifyLanguageChanged();
}

export function notifyHistoryReadChanged(): void {
  const current = AppStorage.get<number>(HISTORY_READ_REVISION_KEY);
  AppStorage.setOrCreate<number>(HISTORY_READ_REVISION_KEY, current === undefined ? 1 : current + 1);
}

export function notifyGalleryTitleChanged(): void {
  const current = AppStorage.get<number>(GALLERY_TITLE_REVISION_KEY);
  AppStorage.setOrCreate<number>(GALLERY_TITLE_REVISION_KEY, current === undefined ? 1 : current + 1);
}

export function shouldUseChineseUi(): boolean {
  const language = ehSettingsStore.getValue('app_language', 'System');
  if (language === 'zh-CN') {
    return true;
  }
  if (language === 'English') {
    return false;
  }
  return isSystemChineseLanguage();
}

export function shouldShowTagTranslations(): boolean {
  return shouldUseChineseUi() && ehSettingsStore.getValue('show_tag_translations', 'On') === 'On';
}

function isSystemChineseLanguage(): boolean {
  try {
    const systemLanguage = i18n.System.getSimplifiedLanguage();
    const supportedLanguages: Array<string> = ['zh-Hans'];
    return i18n.I18NUtil.getBestMatchLocale(systemLanguage, supportedLanguages) === 'zh-Hans';
  } catch (error) {
    return false;
  }
}

export function uiText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  return zhText(text);
}

export function uiValue(value: string): string {
  return uiText(value);
}

export function plainTextFromHtml(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function uiStatusText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  if (text.indexOf('Identity authentication mode: ') === 0) {
    return '身份验证模式：' + uiText(text.substring('Identity authentication mode: '.length));
  }
  if (text === 'Loading galleries...') {
    return '正在加载画廊...';
  }
  if (text === 'No results') {
    return '无结果';
  }
  if (text === 'Loading history...') {
    return '正在加载历史...';
  }
  if (text === 'Tap a gallery row to load detail') {
    return '点击画廊条目加载详情';
  }
  if (text === 'Tap a history item to load detail') {
    return '点击历史条目加载详情';
  }
  if (text === 'Reader is ready') {
    return '阅读器已就绪';
  }
  if (text === 'Sign in with an E-Hentai forum account') {
    return '使用 E-Hentai 论坛账号登录';
  }
  if (text === 'Enter ipb_member_id and ipb_pass_hash, or paste a full Cookie header') {
    return '输入 ipb_member_id 和 ipb_pass_hash，或粘贴完整 Cookie 头';
  }
  if (text === 'Finish login in the web page; Cookie will be captured automatically') {
    return '在网页中完成登录，Cookie 会自动捕获';
  }
  if (text === 'No Cookie saved') {
    return '没有保存的 Cookie';
  }
  if (text === 'Persisted Cookie loaded') {
    return '已加载保存的 Cookie';
  }
  if (text === 'Cookie saved') {
    return 'Cookie 已保存';
  }
  if (text === 'Empty Cookie saved') {
    return '已保存空 Cookie';
  }
  if (text === 'Web Cookie captured') {
    return '已捕获网页 Cookie';
  }
  if (text === 'Ability context is not ready') {
    return 'Ability 上下文尚未就绪';
  }
  if (text === 'Username cannot be empty') {
    return '用户名不能为空';
  }
  if (text === 'Password cannot be empty') {
    return '密码不能为空';
  }
  if (text === 'Web sign-in is ready; existing browser verification is kept') {
    return '网页登录已准备好，现有浏览器验证状态会保留';
  }
  if (text === 'Web verification Cookie captured; waiting for login...') {
    return '已捕获网页验证 Cookie，等待登录完成...';
  }
  if (text === 'Waiting for web login...') {
    return '等待网页登录...';
  }
  if (text === 'Web Cookie found, but context is not ready') {
    return '已找到网页 Cookie，但上下文尚未就绪';
  }
  if (text === 'Cookie fields detected') {
    return '已识别 Cookie 字段';
  }
  if (text === 'No known Cookie fields detected') {
    return '未识别到已知 Cookie 字段';
  }
  if (text === 'ipb_member_id is empty') {
    return 'ipb_member_id 为空';
  }
  if (text === 'ipb_pass_hash is empty') {
    return 'ipb_pass_hash 为空';
  }
  if (text === 'ipb_member_id should contain digits only') {
    return 'ipb_member_id 只能包含数字';
  }
  if (text === 'ipb_pass_hash should be 32 lowercase letters or digits') {
    return 'ipb_pass_hash 应为 32 位小写字母或数字';
  }
  if (text === 'Cookie cleared in memory') {
    return '已在内存中清除 Cookie';
  }
  if (text === 'Cookie cleared') {
    return 'Cookie 已清除';
  }
  if (text === 'Cookie session loaded') {
    return '已加载 Cookie 会话';
  }
  if (text === 'Tourist mode') {
    return '游客模式';
  }
  if (text === 'Signed out in memory') {
    return '已在内存中退出登录';
  }
  if (text === 'Signed out') {
    return '已退出登录';
  }
  if (text === 'No setting is selected') {
    return '未选择设置项';
  }
  if (text === 'UConfig requires a signed-in session') {
    return 'UConfig 需要已登录会话';
  }
  if (text === 'My Tags requires a signed-in session') {
    return 'My Tags 需要已登录会话';
  }
  if (text === 'Loading My Tags...') {
    return '正在加载我的标签...';
  }
  if (text === 'Saving My Tags...') {
    return '正在保存我的标签...';
  }
  if (text === 'Saving My Tags settings...') {
    return '正在保存我的标签设置...';
  }
  if (text === 'My Tags loaded') {
    return '我的标签已加载';
  }
  if (text === 'My Tags saved') {
    return '我的标签已保存';
  }
  if (text === 'My Tags settings saved') {
    return '我的标签设置已保存';
  }
  if (text === 'Enter a tag first') {
    return '请先输入标签';
  }
  if (text.indexOf('My Tags load failed: ') === 0) {
    return '我的标签加载失败：' + text.substring('My Tags load failed: '.length);
  }
  if (text.indexOf('My Tags save failed: ') === 0) {
    return '我的标签保存失败：' + text.substring('My Tags save failed: '.length);
  }
  if (text === 'Running network diagnostics...') {
    return '正在运行网络诊断...';
  }
  if (text === 'No other page to jump to') {
    return '没有可跳转的其他页面';
  }
  if (text === 'Random needs a loaded gallery list') {
    return '随机功能需要先加载画廊列表';
  }
  if (text === 'Account filters enabled') {
    return '账号过滤已开启';
  }
  if (text === 'Account filters disabled') {
    return '账号过滤已关闭';
  }
  if (text.indexOf('Save setting failed: ') === 0) {
    return '保存设置失败：' + text.substring('Save setting failed: '.length);
  }
  if (text === 'Downloads: idle') {
    return '下载：空闲';
  }
  if (text === 'Downloads: unavailable') {
    return '下载：不可用';
  }
  if (text.indexOf('Downloads: ') === 0) {
    return '下载：' + text.substring('Downloads: '.length);
  }
  if (text.indexOf('Load failed: ') === 0) {
    return '加载失败：' + text.substring('Load failed: '.length);
  }
  if (text.indexOf('History load failed: ') === 0) {
    return '历史加载失败：' + text.substring('History load failed: '.length);
  }
  if (text.indexOf('Detail load failed: ') === 0) {
    return '详情加载失败：' + text.substring('Detail load failed: '.length);
  }
  if (text.indexOf('Page load failed: ') === 0) {
    return '页面加载失败：' + text.substring('Page load failed: '.length);
  }
  if (text.indexOf('Sign in failed: ') === 0) {
    return '登录失败：' + text.substring('Sign in failed: '.length);
  }
  if (text.indexOf('Cookie load failed: ') === 0) {
    return 'Cookie 加载失败：' + text.substring('Cookie load failed: '.length);
  }
  if (text.indexOf('Cookie save failed: ') === 0) {
    return 'Cookie 保存失败：' + text.substring('Cookie save failed: '.length);
  }
  if (text.indexOf('Cookie clear failed: ') === 0) {
    return 'Cookie 清除失败：' + text.substring('Cookie clear failed: '.length);
  }
  if (text.indexOf('Web Cookie save failed: ') === 0) {
    return '网页 Cookie 保存失败：' + text.substring('Web Cookie save failed: '.length);
  }
  if (text.indexOf('Signed in but Cookie save failed: ') === 0) {
    return '已登录，但 Cookie 保存失败：' + text.substring('Signed in but Cookie save failed: '.length);
  }
  if (text.indexOf('Settings load failed: ') === 0) {
    return '设置加载失败：' + text.substring('Settings load failed: '.length);
  }
  if (text.indexOf('Sign out failed: ') === 0) {
    return '退出登录失败：' + text.substring('Sign out failed: '.length);
  }
  if (text.indexOf('Save failed: ') === 0) {
    return '保存失败：' + text.substring('Save failed: '.length);
  }
  if (text.indexOf('Load more failed: ') === 0) {
    return '加载更多失败：' + text.substring('Load more failed: '.length);
  }
  if (text.indexOf('Download load failed: ') === 0) {
    return '下载列表加载失败：' + text.substring('Download load failed: '.length);
  }
  if (text.indexOf('Download save failed: ') === 0) {
    return '下载列表保存失败：' + text.substring('Download save failed: '.length);
  }
  if (text.indexOf('Download failed: ') === 0) {
    return '下载失败：' + text.substring('Download failed: '.length);
  }
  if (text.indexOf('Filter load warning: ') === 0) {
    return '过滤规则加载警告：' + text.substring('Filter load warning: '.length);
  }
  if (text.indexOf('Filter save failed: ') === 0) {
    return '过滤规则保存失败：' + text.substring('Filter save failed: '.length);
  }
  if (text === 'Export needs an ability context') {
    return '导出需要 Ability 上下文';
  }
  if (text === 'Preparing export...') {
    return '正在准备导出...';
  }
  if (text === 'Export cancelled') {
    return '已取消导出';
  }
  if (text.indexOf('Export saved: ') === 0) {
    return '导出已保存：' + text.substring('Export saved: '.length);
  }
  if (text.indexOf('Export write failed: ') === 0) {
    return '导出写入失败：' + text.substring('Export write failed: '.length);
  }
  if (text.indexOf('Export picker failed: ') === 0) {
    return '导出文件选择失败：' + text.substring('Export picker failed: '.length);
  }
  if (text.indexOf('Invalid proxy host: ') === 0) {
    return '代理主机无效：' + text.substring('Invalid proxy host: '.length);
  }
  if (text.indexOf('Invalid proxy port: ') === 0) {
    return '代理端口无效：' + text.substring('Invalid proxy port: '.length);
  }
  if (text === 'Restore download items needs an ability context') {
    return '恢复下载项需要 Ability 上下文';
  }
  if (text === 'Preparing public Downloads access...') {
    return '正在准备访问系统下载目录...';
  }
  if (text === 'Preparing app internal storage...') {
    return '正在准备应用内部存储...';
  }
  if (text === 'Switching download location...') {
    return '正在切换下载位置...';
  }
  if (text === 'Download location change cancelled') {
    return '已取消切换下载位置';
  }
  if (text === 'Download location switched without migration') {
    return '下载位置已切换，未迁移文件';
  }
  if (text.indexOf('Migrated downloads: ') === 0) {
    return '下载文件迁移完成：' + text.substring('Migrated downloads: '.length)
      .replace(' files, ', ' 个文件，')
      .replace('.', '。');
  }
  if (text.indexOf('Download migration failed: ') === 0) {
    return '下载文件迁移失败：' + text.substring('Download migration failed: '.length);
  }
  if (text.indexOf('Download location change failed: ') === 0) {
    return '下载位置切换失败：' + text.substring('Download location change failed: '.length);
  }
  if (text === 'Download location needs app context') {
    return '切换下载位置需要 Ability 上下文';
  }
  if (text === 'Downloads access was not granted') {
    return '未授权访问下载目录';
  }
  if (text === 'Scanning downloaded folders...') {
    return '正在扫描已下载文件夹...';
  }
  if (text.indexOf('Restored downloads: ') === 0) {
    return '恢复下载项：' + text.substring('Restored downloads: '.length)
      .replace(' added, ', ' 个新增，')
      .replace(' updated, ', ' 个更新，')
      .replace(' migrated, ', ' 个迁移，')
      .replace(' metadata rebuilt, ', ' 个元数据重建，')
      .replace(' Fetched ', ' 已抓取 ')
      .replace(' details.', ' 个详情。')
      .replace(' Downloads access was not granted; scanned app files only.', ' 未授权访问下载目录，仅扫描应用文件。');
  }
  if (text.indexOf('Restore downloads failed: ') === 0) {
    return '恢复下载项失败：' + text.substring('Restore downloads failed: '.length);
  }
  if (text.indexOf('Export load failed: ') === 0) {
    return '导出读取数据失败：' + text.substring('Export load failed: '.length);
  }
  if (text === 'Import needs an ability context') {
    return '导入需要 Ability 上下文';
  }
  if (text === 'Select backup file to import...') {
    return '请选择要导入的备份文件...';
  }
  if (text === 'Import cancelled') {
    return '已取消导入';
  }
  if (text === 'Import failed: not a valid EhViewer backup file') {
    return '导入失败：不是有效的 EhViewer 备份文件';
  }
  if (text === 'Importing Android data...') {
    return '正在导入 Android 数据...';
  }
  if (text === 'Import complete') {
    return '导入完成';
  }
  if (text.indexOf('Import complete: Android data ') === 0) {
    return 'Android 数据导入完成：' + text.substring('Import complete: Android data '.length)
      .replace('history ', '历史 ')
      .replace('downloads ', '下载 ')
      .replace('local favorites ', '本地收藏 ')
      .replace('labels ', '标签 ')
      .replace('filters ', '过滤 ')
      .replace('searches ', '搜索 ')
      .replace('bookmarks ', '书签 ');
  }
  if (text.indexOf('Import save failed: ') === 0) {
    return '导入保存失败：' + text.substring('Import save failed: '.length);
  }
  if (text.indexOf('Import failed: ') === 0) {
    return '导入失败：' + text.substring('Import failed: '.length);
  }
  if (text.indexOf('Import picker failed: ') === 0) {
    return '导入文件选择失败：' + text.substring('Import picker failed: '.length);
  }
  if (text.indexOf('Cache limit saved: ') === 0) {
    return '缓存上限已保存：' + text.substring('Cache limit saved: '.length)
      .replace('. Cleared oldest cache: ', '。已清理最旧缓存：')
      .replace(/\.$/, '。');
  }
  if (text.indexOf('Cleared cache: ') === 0) {
    return '已清除缓存：' + text.substring('Cleared cache: '.length)
      .replace(' pages, ', ' 个页面，')
      .replace(' images, ', ' 张图片，')
      .replace(/\.$/, '。');
  }
  if (text === 'Clean redundancy needs an ability context') {
    return '清理冗余需要 Ability 上下文';
  }
  if (text === 'No redundant downloaded galleries') {
    return '没有冗余下载画廊';
  }
  if (text.indexOf('Cleaned redundancy: ') === 0) {
    return '已清理冗余：' + text.substring('Cleaned redundancy: '.length)
      .replace(' folders, ', ' 个文件夹，')
      .replace(' files, ', ' 个文件，')
      .replace(/\.$/, '。');
  }
  if (text.indexOf('Clean redundancy failed: ') === 0) {
    return '清理冗余失败：' + text.substring('Clean redundancy failed: '.length);
  }
  if (text.indexOf('Saved network setting: ') === 0) {
    return '已保存网络设置：' + text.substring('Saved network setting: '.length);
  }
  if (text.indexOf('Saved: ') === 0) {
    return '已保存：' + text.substring('Saved: '.length);
  }
  if (text === 'Theme refreshed') {
    return '主题已刷新';
  }
  if (text.indexOf('Network diagnostics: ') === 0) {
    return '网络诊断：' + text.substring('Network diagnostics: '.length);
  }
  if (text === 'Cannot bookmark image search') {
    return '无法将图片搜索添加为书签';
  }
  if (text === 'Duplicate bookmark') {
    return '已存在相同书签';
  }
  if (text === 'Duplicate bookmark name') {
    return '书签名称已存在';
  }
  if (text === 'Bookmark name is empty') {
    return '书签名称不能为空';
  }
  if (text === 'Bookmark added') {
    return '已添加书签';
  }
  if (text === 'Bookmark removed') {
    return '已删除书签';
  }
  if (text === 'Bookmark updated') {
    return '书签已更新';
  }
  if (text === 'Bookmark update failed') {
    return '书签更新失败';
  }
  const composite = translateCompositeUiStatus(text);
  if (composite !== text) {
    return composite;
  }
  return uiText(text);
}

interface UiStatusPrefixTranslation {
  source: string;
  target: string;
}

const UI_STATUS_PREFIX_TRANSLATIONS: UiStatusPrefixTranslation[] = [
  { source: 'Archive failed: ', target: '存档失败：' },
  { source: 'Comment vote failed: ', target: '评论投票失败：' },
  { source: 'Cookie load failed, using current session: ', target: 'Cookie 加载失败，继续使用当前会话：' },
  { source: 'Cover search failed: ', target: '封面搜索失败：' },
  { source: 'Check for updates failed: ', target: '检查更新失败：' },
  { source: 'Delete history failed: ', target: '删除历史记录失败：' },
  { source: 'Download path cache refreshed: ', target: '下载路径缓存已刷新：' },
  { source: 'Refresh download path cache failed: ', target: '刷新下载路径缓存失败：' },
  { source: 'Exporting ', target: '正在导出 ' },
  { source: 'Favorite failed: ', target: '收藏操作失败：' },
  { source: 'Filter rule added: ', target: '已添加过滤规则：' },
  { source: 'H@H failed: ', target: 'H@H 失败：' },
  { source: 'Invalid gallery id: ', target: '无效的画廊 ID：' },
  { source: 'Jump failed: ', target: '跳转失败：' },
  { source: 'Loading detail for gid ', target: '正在加载画廊详情，GID ' },
  { source: 'Loading page ', target: '正在加载第 ' },
  { source: 'Loading preview page ', target: '正在加载预览页 ' },
  { source: 'Log exported: ', target: '日志已导出：' },
  { source: 'Network diagnostics exported: ', target: '网络诊断已导出：' },
  { source: 'Open link failed: ', target: '打开链接失败：' },
  { source: 'Opening browser: ', target: '正在打开浏览器：' },
  { source: 'Page URL load failed: ', target: '页面 URL 加载失败：' },
  { source: 'Preview page load failed: ', target: '预览页加载失败：' },
  { source: 'Queued: ', target: '已排队：' },
  { source: 'Queued ', target: '已排队 ' },
  { source: 'Rating failed: ', target: '评分失败：' },
  { source: 'Rating submitted: ', target: '评分已提交：' },
  { source: 'Reader launch failed: ', target: '启动阅读器失败：' },
  { source: 'Removed: ', target: '已移除：' },
  { source: 'Removed ', target: '已移除 ' },
  { source: 'Resolving page ', target: '正在解析第 ' },
  { source: 'Restored ', target: '已恢复 ' },
  { source: 'Rule already exists: ', target: '规则已存在：' },
  { source: 'Share failed: ', target: '分享失败：' },
  { source: 'Stopped: ', target: '已停止：' },
  { source: 'Stopped ', target: '已停止 ' },
  { source: 'Tag definition failed: ', target: '标签定义加载失败：' },
  { source: 'Tag refresh failed: ', target: '标签刷新失败：' },
  { source: 'Tag vote failed: ', target: '标签投票失败：' },
  { source: 'Torrent failed: ', target: '种子加载失败：' },
  { source: 'Cleared page cache: ', target: '已清理页面缓存：' },
  { source: 'Preview page ', target: '预览页 ' },
  { source: 'Page ', target: '第 ' },
  { source: 'Selected ', target: '已选择 ' }
];

const UI_STATUS_FRAGMENT_TRANSLATIONS: UiStatusPrefixTranslation[] = [
  { source: ' downloaded galleries', target: ' 个已下载画廊' },
  { source: ' selected downloads', target: ' 个选中的下载项' },
  { source: ' download items', target: ' 个下载项' },
  { source: ' history items', target: ' 条历史记录' },
  { source: ' local favorites', target: ' 个本地收藏' },
  { source: ' metadata rebuilt', target: ' 个元数据已重建' },
  { source: ' galleries', target: ' 个画廊' },
  { source: ' entries', target: ' 个条目' },
  { source: ' loaded', target: ' 已加载' },
  { source: ' unavailable', target: ' 不可用' },
  { source: ' pages', target: ' 页' },
  { source: ' failed', target: ' 失败' }
];

function translateCompositeUiStatus(text: string): string {
  let translated = text;
  for (let i = 0; i < UI_STATUS_PREFIX_TRANSLATIONS.length; i++) {
    const item = UI_STATUS_PREFIX_TRANSLATIONS[i];
    if (text.startsWith(item.source)) {
      translated = item.target + zhText(text.substring(item.source.length));
      break;
    }
  }
  if (translated === text) {
    return text;
  }
  for (let i = 0; i < UI_STATUS_FRAGMENT_TRANSLATIONS.length; i++) {
    const item = UI_STATUS_FRAGMENT_TRANSLATIONS[i];
    translated = translated.split(item.source).join(item.target);
  }
  return translated;
}

export function uiPageText(prefix: string, page: number): string {
  return shouldUseChineseUi() ? prefix + page.toString() + ' 页' : prefix + page.toString();
}

export function zhText(text: string): string {
  const favoriteSlotMatch = /^Favorites\s+(\d+)$/.exec(text);
  if (favoriteSlotMatch !== null) {
    return '收藏夹 ' + favoriteSlotMatch[1];
  }
  if (text.endsWith(' stars and up')) {
    return text.replace(' stars and up', ' 星以上');
  }
  const belowStarsMatch = /^Below\s+(\d+)\s+stars$/.exec(text);
  if (belowStarsMatch !== null) {
    return belowStarsMatch[1] + ' 星以下';
  }
  const pageCountMatch = /^(\d+)\s+pages$/.exec(text);
  if (pageCountMatch !== null) {
    return pageCountMatch[1] + ' 页';
  }
  const favoredCountMatch = /^(\d+)\s+favored$/.exec(text);
  if (favoredCountMatch !== null) {
    return favoredCountMatch[1] + ' 次收藏';
  }
  const previewCountMatch = /^(\d+)\s+thumbnails\s+\/\s+(\d+)\s+pages$/.exec(text);
  if (previewCountMatch !== null) {
    return previewCountMatch[1] + ' 个缩略图 / ' + previewCountMatch[2] + ' 页';
  }
  switch (text) {
    case 'Homepage': return '主页';
    case 'Subscription': return '订阅';
    case 'What\'s Hot': return '热门';
    case 'Whats Hot': return '热门';
    case 'Top Lists': return '排行';
    case 'Favourite': return '收藏';
    case 'Favorites': return '收藏';
    case 'All favorites': return '全部收藏';
    case 'Favorite folders': return '收藏夹';
    case 'Bookmarks': return '书签栏';
    case 'Bookmark settings': return '书签设置';
    case 'Add bookmark': return '添加书签';
    case 'Bookmark name': return '书签名称';
    case 'No bookmarks': return '这里是书签栏';
    case 'Tap plus to bookmark the current gallery list': return '点击“+”添加当前画廊列表状态';
    case 'All site': return '全站';
    case 'Filter Off': return '过滤关闭';
    case 'Move up': return '上移';
    case 'Move down': return '下移';
    case 'Local Favorites': return '本地收藏';
    case 'Add to favorites': return '添加到收藏';
    case 'Remember favorite collection': return '记住收藏夹';
    case 'Choose favorite collection': return '选择收藏夹';
    case 'Adding to local favorites...': return '正在添加到本地收藏...';
    case 'Added to local favorites': return '已添加到本地收藏';
    case 'Removing from local favorites...': return '正在移出本地收藏...';
    case 'Removed from local favorites': return '已移出本地收藏';
    case 'Local favorites unavailable': return '本地收藏不可用';
    case 'History': return '历史';
    case 'Downloads': return '下载';
    case 'Download': return '下载';
    case 'Added to download list and started': return '已加入下载列表并开始下载';
    case 'Download stopped': return '已停止下载';
    case 'Download queued': return '已加入下载队列';
    case 'Download queued for update': return '已加入更新下载队列';
    case 'Settings': return '设置';
    case 'Preferences': return '偏好设置';
    case 'Gallery list and search': return '画廊列表与搜索';
    case 'Watched tags': return '关注标签';
    case 'Popular galleries': return '热门画廊';
    case 'Ranking tables': return '排行榜';
    case 'Cloud and local favorites': return '云端与本地收藏';
    case 'Recent reading': return '最近阅读';
    case 'Queue and labels': return '队列与标签';
    case 'Menu': return '菜单';
    case 'Page': return '页';
    case 'rating': return '评分';
    case 'Cookie session active': return 'Cookie 会话有效';
    case 'Open Settings to sign in': return '打开设置进行登录';
    case 'Back': return '返回';
    case 'Refresh': return '刷新';
    case 'Go': return '搜索';
    case 'Prev': return '上一页';
    case 'Next': return '下一页';
    case 'Previous': return '上一页';
    case 'Zoom out': return '缩小';
    case 'Zoom in': return '放大';
    case 'Hide': return '隐藏';
    case 'Actions': return '操作';
    case 'Select all': return '全选';
    case 'Close': return '关闭';
    case 'Ignore': return '忽略';
    case 'View': return '查看';
    case 'Filter': return '过滤';
    case 'Filter On': return '过滤已开';
    case 'Filter mode': return '过滤模式';
    case 'Jump': return '跳转';
    case 'Seek date': return '按日期查找';
    case 'Random': return '随机';
    case 'Image search': return '图片搜索';
    case 'Select image': return '选择图片';
    case 'From album': return '从相册选择';
    case 'From file': return '从文件选择';
    case 'Similarity scan': return '相似扫描';
    case 'Only cover search': return '仅搜索封面';
    case 'Upload original image': return '上传原图';
    case 'Selected image': return '已选择图片';
    case 'No image selected': return '未选择图片';
    case 'Search image': return '搜索图片';
    case 'Image selected': return '图片已选择';
    case 'Original image selected': return '已选择原图';
    case 'Compatible image selected': return '已选择兼容图';
    case 'Image selection failed': return '图片选择失败';
    case 'Preparing image...': return '正在准备图片...';
    case 'Search': return '搜索';
    case 'Search current text': return '搜索当前文本';
    case 'Search history': return '搜索历史';
    case 'Search once to create suggestions': return '搜索一次后会显示历史建议';
    case 'Search history appears before typing; tag tips appear while typing': return '输入前显示搜索历史，输入时显示标签提示';
    case 'Open gallery': return '打开画廊';
    case 'Open page': return '打开页面';
    case 'Specify tag': return '指定标签';
    case 'Specify uploader': return '指定上传者';
    case 'Search galleries': return '搜索画廊';
    case 'Search downloads': return '搜索下载';
    case 'Gallery Info': return '画廊信息';
    case 'More information': return '查看更多信息';
    case 'Copied to clipboard': return '已复制到剪贴板';
    case 'Copy failed': return '复制失败';
    case 'Key': return '项目';
    case 'Value': return '值';
    case 'Gid': return 'Gid';
    case 'Token': return 'Token';
    case 'URL': return 'URL';
    case 'Jpn Title': return '日文标题';
    case 'Category': return '分类';
    case 'Favorite count': return '收藏数';
    case 'Rating count': return '评分数';
    case 'Torrents': return '种子';
    case 'No torrents': return '没有可用的种子';
    case 'Seeds': return '做种';
    case 'Magnet link copied': return '磁力链接已复制';
    case 'Magnet link unavailable': return '磁力链接不可用';
    case 'Torrent URL': return '种子 URL';
    case 'Favorite name': return '收藏夹名';
    case 'Advanced': return '高级';
    case 'General': return '一般';
    case 'Privacy': return '隐私';
    case 'About': return '关于';
    case 'Advanced search': return '高级搜索';
    case 'Options': return '选项';
    case 'Pages': return '页数';
    case 'Disable default filter': return '禁用默认过滤器';
    case 'Normal': return '普通';
    case 'General search': return '一般搜索';
    case 'Subscription search': return '订阅搜索';
    case 'Uploader search': return '指定上传者';
    case 'Tag search': return '标签搜索';
    case 'All categories': return '全部分类';
    case 'Any rating': return '任意评分';
    case 'No rating limit': return '不限制';
    case 'Name': return '名称';
    case 'Description': return '描述';
    case 'Torrent': return '种子';
    case 'Has torrent': return '有种子';
    case 'Expunged': return '已删除';
    case 'Low power': return '弱标签';
    case 'Downvoted': return '低票标签';
    case 'No lang filter': return '不过滤语言';
    case 'No uploader filter': return '不过滤上传者';
    case 'No tag filter': return '不过滤标签';
    case 'From page': return '起始页';
    case 'To page': return '结束页';
      case 'Information': return '信息';
      case 'Tags': return '标签';
      case 'Enter new tag': return '输入新标签';
      case 'Show Tagged Galleries': return '显示含此标签的画廊';
      case 'Show Tag Definition': return '显示标签定义';
      case 'Tag vote submitted': return '标签投票已提交';
      case 'Tag vote requires gallery API key': return '标签投票需要已加载的画廊会话';
      case 'Tag definition unavailable': return '标签定义不可用';
      case 'Loading...': return '正在加载...';
      case 'Load failed': return '加载失败';
      case 'No galleries': return '没有画廊';
    case 'Please wait...': return '请稍候...';
    case 'Migrating downloaded files...': return '正在迁移下载文件...';
    case 'Switching download location...': return '正在切换下载位置...';
    case 'Rebuilding downloaded metadata...': return '正在重建下载元数据...';
    case 'Rebuilding imported history metadata...': return '正在重建导入历史元数据...';
    case 'Creating download archive...': return '正在生成下载压缩包...';
    case 'Importing Android data...': return '正在导入 Android 数据...';
    case 'Loading tags...': return '正在加载标签...';
    case 'Loading previews...': return '正在加载预览...';
    case 'Loading comments...': return '正在加载评论...';
    case 'Loading rating...': return '正在加载评分...';
    case 'No tags parsed': return '暂无标签';
    case 'Previews': return '预览';
    case 'No previews': return '暂无预览';
    case 'Comments': return '评论';
    case 'See all': return '查看全部';
    case 'View all': return '查看全部';
    case 'Filter rules': return '过滤规则';
    case 'Filter text': return '过滤文本';
    case 'Uploader': return '上传者';
    case 'Tag': return '标签';
    case 'Tag:Namespace': return '标签:命名空间';
    case 'Title': return '标题';
    case 'Add': return '添加';
    case 'Remove': return '删除';
    case 'On': return '开';
    case 'Off': return '关';
    case 'No filters': return '没有过滤规则';
    case 'Add a filter rule above to hide matching galleries from lists.': return '添加过滤规则后，匹配的画廊会在列表中隐藏。';
    case 'Mode: tap to cycle — Title / Uploader / Tag / Tag:Namespace': return '模式：点击切换 — 标题 / 上传者 / 标签 / 标签:命名空间';
    case 'comments': return '条评论';
    case 'total': return '条';
    case 'Anonymous': return '匿名';
    case 'No comments': return '暂无评论';
    case 'Posted': return '发布时间';
    case 'Parent': return '父级';
    case 'Visible': return '可见性';
    case 'Language': return '语言';
    case 'File Size': return '文件大小';
    case 'Length': return '页数';
    case 'Rating': return '评分';
    case 'Favorited': return '已收藏';
    case 'Favorite': return '收藏';
    case 'Archive': return '存档';
    case 'Archive -': return '存档 -';
    case 'Save Archive': return '存档';
    case 'Similar': return '相似画廊';
    case 'Search cover': return '搜索封面';
    case 'No H@H archives': return '没有可用的 H@H 档案';
    case 'No archiver options': return '没有可用的档案选项';
    case 'Loading...': return '加载中...';
    case 'Submitting...': return '正在提交...';
    case 'Parsed H@H archive list': return '已解析 H@H 档案列表';
    case 'Parsed archiver options': return '已解析档案选项';
    case 'H@H download request submitted': return 'H@H 下载请求已提交';
    case 'Archiver download URL ready': return '档案下载链接已就绪';
    case 'Archive download started': return '存档已开始下载到下载目录';
    case 'Archive download failed': return '存档下载失败';
    case 'Share': return '分享';
    case 'Save': return '保存';
    case 'Save to album': return '保存到相册';
    case 'Save to...': return '保存到…';
    case 'Saved to album': return '已保存到相册';
    case 'Save failed': return '保存失败';
    case 'Export': return '导出';
    case 'Import': return '导入';
    case 'Rate': return '评分';
    case 'Cancel': return '取消';
    case 'Delete history': return '删除历史';
    case 'Submit': return '提交';
    case 'Read': return '阅读';
    case 'Queued': return '已加入';
    case 'Original': return '原图';
    case 'Resampled': return '压缩图';
    case 'Info': return '信息';
    case 'Retry': return '重试';
    case 'Page URL': return '页面地址';
    case 'Image URL': return '图片地址';
    case 'Show Key': return '显示密钥';
    case 'Retry Key': return '重试密钥';
    case 'Fit': return '适配';
    case 'Fit width': return '匹配宽度';
    case 'Fit height': return '匹配长度';
    case 'Actual size': return '原始尺寸';
    case 'Fit screen': return '匹配屏幕';
    case 'Fixed scale': return '固定缩放';
    case 'Smart fit': return '匹配屏幕';
    case 'Image page failed to load': return '图片页面加载失败';
    case 'Image page is loading': return '图片页面加载中';
    case 'Reader background': return '阅读器背景';
    case 'Background color behind reader pages': return '阅读器页面背后的背景颜色';
    case 'Black': return '黑色';
    case 'White': return '白色';
    case 'Deep gray': return '深灰';
    case 'unknown uploader': return '未知上传者';
    case 'Clear all': return '清空';
    case 'Remove': return '移除';
    case 'Start all': return '全部开始';
    case 'Stop all': return '全部停止';
    case 'Clear done': return '清除完成';
    case 'State': return '状态';
    case 'Label': return '标签';
    case 'Add': return '添加';
    case 'Delete': return '删除';
    case 'New label': return '新标签';
    case 'All': return '全部';
    case 'Default': return '默认';
    case 'Idle': return '空闲';
    case 'Waiting': return '等待中';
    case 'Downloading': return '下载中';
    case 'Downloaded': return '已下载';
    case 'Failed': return '失败';
    case 'Updating': return '更新中';
    case 'Invalid': return '无效';
    case 'Status': return '状态';
    case 'Current status filter': return '当前状态筛选';
    case 'Sort': return '排序';
    case 'Selected': return '已选择';
    case 'Sign in': return '登录';
    case 'Sign out': return '退出登录';
    case 'Signed in': return '已登录';
    case 'Tourist': return '游客';
    case 'Guest mode': return '游客模式';
    case 'Register': return '注册';
    case 'Username': return '用户名';
    case 'Password': return '密码';
    case 'Sign in via WebView': return '通过网页登录';
    case 'Sign in via Cookies': return '通过 Cookie 登录';
    case 'Cookie Sign In': return 'Cookie 登录';
    case 'Use this when password login needs captcha, or when importing an ExHentai session.': return '当密码登录需要验证码，或导入 ExHentai 会话时使用。';
    case 'Full Cookie header': return '完整 Cookie 头';
    case 'Clear': return '清除';
    case 'OK': return '确定';
    case 'Session': return '会话';
    case 'UConfig': return '账号配置';
    case 'My Tags': return '我的标签';
    case 'Blocked': return '屏蔽';
    case 'Tag name': return '标签名';
    case 'Save': return '保存';
    case 'Refresh': return '刷新';
    case 'No tags': return '无标签';
    case 'Website settings': return '网页设置';
    case 'Default tagset': return '默认标签集';
    case 'Default color': return '默认颜色';
    case 'Save settings': return '保存设置';
    case 'Manage watched and hidden tags for the selected site.': return '管理当前站点的订阅和屏蔽标签。';
    case 'Watched tags are used by the subscription page': return '订阅标签会用于订阅页面';
    case 'Migration': return '迁移状态';
    case 'Open': return '打开';
    case 'Run': return '运行';
    case 'Scan': return '扫描';
    case 'Link': return '链接';
    case 'Not migrated': return '未迁移';
    case 'Available': return '可用';
    case 'No session': return '无会话';
    case 'Theme': return '主题';
    case 'Light': return '亮色';
    case 'Dark': return '暗色';
    case 'Black': return '黑色';
    case 'On': return '开';
    case 'Off': return '关';
    case 'System': return '跟随系统';
    case 'English': return '英语';
    case 'zh-CN': return '简体中文';
    case 'Portrait': return '竖屏';
    case 'Landscape': return '横屏';
    case 'Auto rotate': return '自动旋转';
    case 'Match image': return '匹配图片';
    case 'Left to right': return '从左至右';
    case 'Right to left': return '从右至左';
    case 'Top to bottom': return '从上至下';
    case 'Vertical': return '纵向';
    case 'Top left': return '左上角';
    case 'Top right': return '右上角';
    case 'Bottom left': return '左下角';
    case 'Bottom right': return '右下角';
    case 'Center': return '中心';
    case 'Beginning': return '开头';
    case 'Last read': return '上次阅读';
    case 'End': return '末尾';
    case 'Not set': return '未设置';
    case 'App files': return '应用文件';
    case 'Small': return '小';
    case 'Medium': return '中';
    case 'Large': return '大';
    case 'XLarge': return '超大';
    case 'Compact': return '紧凑';
    case 'Loose': return '宽松';
    case 'Detail': return '详情';
    case 'Thumb': return '缩略图';
    case 'Extended': return '扩展';
    case 'Auto': return '自动';
    case 'HTTP': return 'HTTP';
    case 'SOCKS': return 'SOCKS';
    case 'Read cache size': return '阅读缓存大小';
    case 'App language': return '应用语言';
    case 'Proxy': return '代理';
    case 'Network diagnostics': return '网络诊断';
    case 'Built-in hosts': return '内置 hosts';
    case 'Built EX hosts': return '内置 EX hosts';
    case 'DNS over HTTPS': return 'DNS over HTTPS';
    case 'Secure DNS (DoH)': return '安全 DNS（DoH）';
    case 'Domain fronting': return '域名前置';
    case 'Direct connection check': return '直连检测';
    case 'Direct connection available, domain fronting disabled': return '可直接访问，已关闭域名前置';
    case 'Direct connection unavailable, domain fronting enabled': return '无法直接访问，开启域名前置';
    case 'Account, site, gallery list and comments': return '账号、站点、画廊列表和评论';
    case 'Reader direction, scaling and screen behavior': return '阅读方向、缩放和屏幕行为';
    case 'Location, threads, preload and cleanup': return '位置、线程、预加载和清理';
    case 'Lock and local data controls': return '锁定和本地数据控制';
    case 'Network, cache, hosts and diagnostics': return '网络、缓存、hosts 和诊断';
    case 'Version and license': return '版本和许可证';
    case 'Settings follow the original Android header groups': return '设置按原 Android 应用分组';
    case 'Account session': return '账号会话';
    case 'Cookie session is available. Open to replace or inspect cookies.': return 'Cookie 会话可用。打开后可替换或查看 Cookie。';
    case 'Open password, WebView or Cookie sign-in. This matches the original startup sign-in flow.': return '打开密码、网页或 Cookie 登录，保持原应用启动登录流程。';
    case 'Clear the persisted identity cookies': return '清除已保存的身份 Cookie';
    case 'Original app cycles Light, Dark and Black from drawer/footer and Settings': return '原应用可在抽屉/底部和设置中切换亮色、暗色、黑色主题';
    case 'Identity cookies': return '身份 Cookie';
    case 'View or import ipb_member_id, ipb_pass_hash and igneous': return '查看或导入 ipb_member_id、ipb_pass_hash 和 igneous';
    case 'Gallery site': return '画廊站点';
    case 'Original setting chooses E-Hentai or ExHentai where supported': return '按原设置选择 E-Hentai 或可用时的 ExHentai';
    case 'Account configuration page, requires sign in': return '账号配置页面，需要登录';
    case 'Use account filters': return '使用账号过滤';
    case 'Use filtering options captured from UConfig': return '使用账号配置中抓取的过滤选项';
    case 'User tag set management, requires sign in': return '用户标签集管理，需要登录';
    case 'Manage watched and hidden tags, requires sign in': return '管理订阅和屏蔽标签，需要登录';
    case 'Launch page': return '启动页面';
    case 'Default start scene after warnings and sign-in checks': return '警告和登录检查后的默认启动页面';
    case 'List mode': return '列表模式';
    case 'Gallery list style from original Android preferences': return '原 Android 偏好中的画廊列表样式';
    case 'Detail size': return '详情大小';
    case 'Gallery detail image and metadata density': return '画廊详情图片和元数据密度';
    case 'Thumb size': return '缩略图大小';
    case 'Thumbnail size used in gallery rows': return '画廊行中使用的缩略图大小';
    case 'History size': return '历史记录数量';
    case 'Maximum stored gallery history records': return '最多保存的画廊历史记录数量';
    case 'Show Japanese title': return '显示日文标题';
    case 'Prefer original title when available': return '可用时优先显示原始标题';
    case 'Show gallery pages': return '显示画廊页数';
    case 'Display page count in gallery list rows': return '在画廊列表中显示页数';
    case 'Show tag translations': return '显示标签翻译';
    case 'Use translated tag labels when data is available': return '有数据时使用翻译后的标签名称';
    case 'Split screen mode': return '分屏模式';
    case 'Use left-right panes on wide screens': return '在宽屏设备上使用左右分栏';
    case 'Follow system dark mode': return '跟随系统深色模式';
    case 'Use Light in system light mode and the selected dark theme in system dark mode': return '系统浅色时使用亮色，系统深色时使用选定的深色主题';
    case 'Dark mode theme': return '深色模式主题';
    case 'Choose Dark or Black when the system enters dark mode': return '系统进入深色模式时使用暗色或黑色主题';
    case 'Keyword/gallery filtering rules': return '关键字/画廊过滤规则';
    case 'Hide matching galleries': return '隐藏匹配的画廊';
    case 'Show EH limits': return '显示 EH 限制';
    case 'Display account and image limits in the drawer': return '在抽屉中显示账号和图片限制';
    case 'Loading EH limits': return '正在加载 EH 配额';
    case 'EH limits unavailable': return 'EH 配额不可用';
    case 'Failed to load EH limits': return 'EH 配额加载失败';
    case 'IP-based limits': return '基于 IP 的配额';
    case 'No quota reset is currently needed': return '当前无需重置配额，请刷新后重试';
    case 'from gallery visits': return '来自画廊访问';
    case 'from torrent completions': return '来自种子完成';
    case 'from archive downloads': return '来自归档下载';
    case 'from Hentai@Home': return '来自 Hentai@Home';
    case 'reset cost': return '重置费用';
    case 'Cellular network warning': return '移动网络警告';
    case 'Warn before network-heavy operations on mobile data': return '使用移动数据进行大量网络操作前提示';
    case 'Connected to cellular networks': return '正在使用移动网络';
    case 'Mobile data warning': return '移动网络警告';
    case 'You are using mobile data. Continue downloading?': return '当前正在使用移动网络，是否继续下载？';
    case 'Continue': return '继续';
    case 'Screen rotation': return '屏幕旋转';
    case 'Reader orientation policy': return '阅读器方向策略';
    case 'Reading direction': return '阅读方向';
    case 'Left-to-right, right-to-left or vertical reader movement': return '从左到右、从右到左或纵向阅读';
    case 'Page scaling': return '页面缩放';
    case 'Fit width, fit height or original page scaling': return '原始尺寸、匹配宽度、匹配长度、匹配屏幕或固定缩放';
    case 'Start position': return '开页位置';
    case 'Where a gallery starts when opened': return '页面打开时的初始对齐位置';
    case 'Auto transfer time': return '自动翻页时间';
    case 'Automatic next-page delay from original seekbar preference': return '原应用滑动条设置的自动下一页延迟';
    case 'Standalone reader': return '独立阅读器';
    case 'Open reader in a standalone ability': return '使用独立 Ability 打开阅读器';
    case 'Keep screen on': return '保持屏幕常亮';
    case 'Prevent screen sleep while reading': return '阅读时防止屏幕休眠';
    case 'Show clock': return '显示时钟';
    case 'Show clock overlay in the reader': return '在阅读器中显示时钟浮层';
    case 'Show progress': return '显示进度';
    case 'Show reader progress overlay': return '在阅读器中显示阅读进度';
    case 'Show battery': return '显示电量';
    case 'Show battery overlay': return '在阅读器中显示电量浮层';
    case 'Volume page': return '音量键翻页';
    case 'Use volume buttons to turn pages': return '使用音量键翻页';
    case 'Reading fullscreen': return '阅读全屏';
    case 'Hide system chrome while reading': return '阅读时隐藏系统界面';
    case 'Custom brightness': return '自定义亮度';
    case 'Enable custom reader brightness': return '启用阅读器自定义亮度';
    case 'Screen lightness': return '屏幕亮度';
    case 'Custom reader brightness when enabled': return '启用后使用自定义阅读亮度';
    case 'Ultra dark mode': return '超暗模式';
    case 'Ultra dark brightness': return '超暗模式亮度';
    case 'Dim reader with a black overlay and minimum system brightness': return '将系统亮度降到最低，并使用黑色遮罩压暗阅读器';
    case 'Black overlay opacity while ultra dark mode is enabled': return '超暗模式开启时黑色遮罩的透明度';
    case 'Download location': return '下载位置';
    case 'Migrate downloaded files to the new location?': return '是否将已下载文件迁移到新的下载位置？';
    case 'Current': return '当前';
    case 'Target': return '目标';
    case 'Switch only': return '仅切换';
    case 'Migrate': return '迁移';
    case 'HarmonyOS file picker/storage mapping for downloaded galleries': return '下载画廊的 HarmonyOS 文件选择器/存储映射';
    case 'App internal storage or public Downloads directory': return '应用内部存储或系统下载目录';
    case 'Multi-thread download': return '多线程下载';
    case 'Number of images downloaded at the same time': return '同时下载的图片数量';
    case 'Preload image': return '预加载图片';
    case 'Reader/download prefetch count': return '阅读器/下载预取数量';
    case 'Download list pagination': return '下载列表分页';
    case 'Paginate large download lists': return '大型下载列表分页显示';
    case 'Image resolution': return '图片分辨率';
    case 'Requested E-Hentai image size': return '请求的 E-Hentai 图片尺寸';
    case 'Download original image': return '下载原图';
    case 'Prefer original files when available': return '可用时优先下载原始文件';
    case 'Download timeout': return '下载超时';
    case 'Network timeout for image tasks': return '图片任务的网络超时时间';
    case 'Download order ascending': return '按升序下载';
    case 'Store pages in ascending page order': return '按页码升序保存';
    case 'Restore download items': return '恢复下载项';
    case 'Rebuild queue from downloaded folders': return '从已下载文件夹重建队列';
    case 'Clean redundancy': return '清理冗余';
    case 'Delete downloaded gallery folders that are no longer in the download list': return '删除已不在下载列表中的画廊文件夹';
    case 'Identity authentication': return '身份验证';
    case 'Verify identity when the app returns from background': return '应用从后台恢复时验证身份';
    case 'Fingerprint first': return '指纹优先';
    case 'Face first': return '人脸优先';
    case 'Password first': return '密码优先';
    case 'Biometric lock enabled: app will prompt for fingerprint/face on resume': return '身份验证已开启：应用恢复时会提示指纹/人脸验证';
    case 'Biometric lock disabled': return '身份验证已关闭';
    case 'Identity authentication enabled: app will verify identity on resume': return '身份验证已开启：应用恢复时会验证身份';
    case 'Identity authentication disabled': return '身份验证已关闭';
    case 'Identity authentication mode: ': return '身份验证模式：';
    case 'Identity authentication requires an ability context': return '身份验证需要 Ability 上下文';
    case 'Identity authentication required': return '需要身份验证';
    case 'Unlock to continue using EhViewer': return '解锁后继续使用 EhViewer';
    case 'Privacy mode': return '隐私模式';
    case 'Prevent screenshots and insecure previews': return '禁止截图、录屏和不安全预览';
    case 'Save parse error body': return '保存解析错误正文';
    case 'Persist parser failures for debugging': return '保存解析失败的网页正文用于调试';
    case 'Save crash log': return '保存日志';
    case 'Persist crash logs locally': return '在本地保存崩溃日志';
    case 'Persist app errors and debug messages locally': return '在本地保存应用错误和调试信息';
    case 'Dump logcat': return '导出 logcat';
    case 'Android logcat equivalent needs Harmony logging export': return 'Android logcat 等价功能需要 Harmony 日志导出';
    case 'Export log': return '导出日志';
    case 'Save the local app log to a text file': return '将本地应用日志保存为文本文件';
    case 'Clear saved log': return '清空已保存日志';
    case 'Delete the local app log file': return '删除本地应用日志和解析错误正文';
    case 'Clear download path cache': return '清除下载路径缓存';
    case 'Refresh cached file path and size lookups': return '刷新缓存的文件路径和大小查询';
    case 'Clear cache': return '清除缓存';
    case 'Drop reader image and page caches': return '清除阅读器图片和页面缓存';
    case 'Reader cache budget': return '阅读器缓存容量';
    case 'Language override': return '语言覆盖设置';
    case 'System proxy or direct connection': return '系统代理或直连';
    case 'System proxy, direct connection or HTTP proxy': return '系统代理、直连或 HTTP 代理';
    case 'Proxy host': return '代理主机';
    case 'Host or IP address for custom proxy': return '自定义代理的主机名或 IP 地址';
    case 'Host or IP address for HTTP proxy': return 'HTTP 代理的主机名或 IP 地址';
    case 'Proxy port': return '代理端口';
    case 'Proxy username': return '代理用户名';
    case 'Optional proxy authentication username': return '可选的代理认证用户名';
    case 'Proxy password': return '代理密码';
    case 'Optional proxy authentication password': return '可选的代理认证密码';
    case 'Proxy exclusions': return '代理排除列表';
    case 'Comma-separated hosts that should bypass the proxy': return '用英文逗号分隔不走代理的主机';
    case 'Test E, EX, forums and repo connectivity with current settings': return '按当前设置测试 E、EX、论坛和仓库连通性';
    case 'Force bundled host overrides; leave Off for normal Cloudflare DNS': return '强制使用内置 host；正常 Cloudflare DNS 请保持关闭';
    case 'Force bundled ExHentai host overrides; leave Off unless your network needs them': return '强制使用内置 ExHentai host；仅在网络需要时开启';
    case 'Use DoH resolver': return '使用 DoH 解析器';
    case 'Resolve DNS pollution in some regions': return '解决某些地区的 DNS 污染问题';
    case 'Original network compatibility switch': return '原应用网络兼容性开关';
    case 'Bypass SNI blocking using built-in host fronting': return '使用内置 hosts 绕过 SNI 封锁';
    case 'Use direct connection when the selected site responds within 5s': return '所选站点 5 秒内可直连时不使用 hosts 和域名前置';
    case 'Export data': return '导出数据';
    case 'Save settings, history, downloads and filter rules to a JSON file': return '将设置、历史记录、下载和过滤规则保存为 JSON 文件';
    case 'Import data': return '导入数据';
    case 'Restore from a JSON backup or Android exported database': return '从 JSON 备份或原安卓导出数据库恢复';
    case 'Wi-Fi server/client': return 'Wi-Fi 服务器/客户端';
    case 'Original Wi-Fi transfer tools': return '原应用 Wi-Fi 传输工具';
    case 'Declaration': return '声明';
    case 'Original declaration and project notice': return '原应用声明和项目说明';
    case 'Current HarmonyOS repository': return '当前 HarmonyOS 仓库';
    case 'Author': return '作者';
    case 'xiaojieonly/Ehviewer_CN_SXJ contributors': return 'xiaojieonly/Ehviewer_CN_SXJ 贡献者';
    case 'GitHub release for the current port': return '当前移植版 GitHub release';
    case 'Issue help': return '问题帮助';
    case 'Issue tracker for the current port': return '当前移植版问题反馈';
    case 'License': return '许可证';
    case 'Inherited from original app': return '继承自原应用';
    case 'Version': return '版本';
    case 'Git commit': return 'Git 提交';
    case 'Branch and describe from the build workspace': return '构建工作区分支和 describe 信息';
    case 'Check for updates': return '检查更新';
    case 'Check the latest GitHub release': return '检查 GitHub 最新发布版本';
    case 'Disable startup update check': return '关闭启动时自动检查更新';
    case 'New version available': return '发现新版本';
    case 'New version found': return '发现新版本';
    case 'No updates available': return '当前已是最新版本';
    case 'Checking for updates...': return '正在检查更新...';
    case 'Current version': return '当前版本';
    case 'No release notes': return '暂无更新内容';
    case 'Update': return '更新';
    case 'Close automatic updates': return '关闭自动更新';
    case 'Disable startup update check': return '禁用启动时更新检查';
    case 'Donate': return '捐赠';
    case 'Original donation entry': return '原应用捐赠入口';
    case 'Download items will be shown here': return '下载项会显示在这里';
    case 'No items match the current filter': return '没有符合当前过滤条件的项目';
    case 'Pull down to refresh': return '下拉刷新';
    case 'Release to refresh': return '松开刷新';
    case 'Refreshing...': return '正在刷新...';
    case 'All pages loaded': return '已加载全部页面';
    case 'Waiting for toplist.php': return '等待 toplist.php';
    case 'EH': return 'EH';
    case 'EX': return 'EX';
    case 'CK': return 'CK';
    case 'EhViewer': return 'EhViewer';
    case 'H@H': return 'H@H';
    case 'Forums': return '论坛';
    case 'Repo': return '仓库';
    case 'Jump/Seek': return '跳转/按日期查找';
    case 'entries': return '个条目';
    case 'Artist': return '艺术家';
    case 'Group': return '社团';
    case 'Parody': return '原作';
    case 'Character': return '角色';
    case 'Female': return '女性';
    case 'Male': return '男性';
    case 'Mixed': return '混合';
    case 'Cosplayer': return '角色扮演者';
    case 'Other': return '其他';
    case 'Location': return '地点';
    case 'Rows': return '行';
    case 'Below ': return '低于 ';
    case 'artist': return '艺术家';
    case 'group': return '社团';
    case 'parody': return '原作';
    case 'character': return '角色';
    case 'female': return '女性';
    case 'male': return '男性';
    case 'mixed': return '混合';
    case 'language': return '语言';
    case 'cosplayer': return '角色扮演者';
    case 'other': return '其他';
    case 'location': return '地点';
    case 'rows': return '行';
    case 'Doujinshi': return '同人志';
    case 'Manga': return '漫画';
    case 'Artist CG': return '艺术家 CG';
    case 'Game CG': return '游戏 CG';
    case 'Image Set': return '图集';
    case 'Images': return '图片';
    case 'Cosplay': return '角色扮演';
    case 'Asian Porn': return '亚洲色情';
    case 'Non-H': return '非 H';
    case 'Western': return '西方';
    case 'Misc': return '杂项';
    case 'Vote+': return '赞成';
    case 'Vote-': return '反对';
    case 'Adding to favorites...': return '正在添加到收藏...';
    case 'Removing from favorites...': return '正在移出收藏...';
    case 'Deleting My Tags...': return '正在删除我的标签...';
    case 'Refreshing detail...': return '正在刷新详情...';
    case 'Submitting rating...': return '正在提交评分...';
    case 'Preparing cover search...': return '正在准备封面搜索...';
    case 'Detail loaded': return '详情已加载';
    case 'No gallery loaded': return '未加载画廊';
    case 'Read is waiting for preview pages': return '阅读器正在等待预览页';
    case 'Preview pages are unavailable': return '预览页不可用';
    case 'Rating needs a loaded gallery session': return '评分需要已加载的画廊会话';
    case 'Similar search needs a loaded gallery': return '相似搜索需要已加载的画廊';
    case 'Cover image is unavailable': return '封面图片不可用';
    case 'Cover image cache failed': return '封面图片缓存失败';
    case 'Comment vote requires gallery API key': return '评论投票需要画廊 API 密钥';
    case 'Comment is not voteable': return '该评论不可投票';
    case 'Comment vote submitted': return '评论投票已提交';
    case 'Invalid comment vote response': return '评论投票响应无效';
    case 'Torrent URL is unavailable': return '种子 URL 不可用';
    case 'Invalid H@H resolution': return '无效的 H@H 分辨率';
    case 'No H@H client available': return '没有可用的 H@H 客户端';
    case 'No archiver continuation URL': return '未找到存档继续链接';
    case 'No archiver download URL': return '未找到存档下载链接';
    case 'Download needs a loaded gallery': return '下载需要已加载的画廊';
    case 'Download needs app context': return '下载需要应用上下文';
    case 'Download path cache needs an ability context': return '下载路径缓存需要 Ability 上下文';
    case 'Download waits for Wi-Fi or confirmation': return '下载正在等待 Wi-Fi 或用户确认';
    case 'Long press cards to select downloads': return '长按卡片选择下载项';
    case 'No downloaded galleries to select': return '没有可选择的已下载画廊';
    case 'Queued idle and failed downloads': return '已将空闲和失败的下载重新排队';
    case 'Stopped waiting downloads': return '已停止等待中的下载';
    case 'Restore needs app context': return '恢复需要应用上下文';
    case 'Export needs app context': return '导出需要应用上下文';
    case 'Enter a filter text first': return '请先输入过滤文本';
    case 'Filter rule removed': return '已删除过滤规则';
    case 'Clear log needs an ability context': return '清理日志需要 Ability 上下文';
    case 'Saved log cleared': return '已清空保存的日志';
    case 'Log exported': return '日志已导出';
    case 'Network diagnostics exported': return '网络诊断已导出';
    case 'Open link failed: Ability context is not ready': return '打开链接失败：Ability 上下文尚未就绪';
    case 'Share failed: Ability context is not ready': return '分享失败：Ability 上下文尚未就绪';
    case 'Share panel closed': return '分享面板已关闭';
    case 'Reader launch failed: Ability context is not ready': return '启动阅读器失败：Ability 上下文尚未就绪';
    case 'Reader session is empty': return '阅读器会话为空';
    case 'Preview has no page URL': return '预览项没有页面 URL';
    case 'Page loaded': return '页面已加载';
    case 'Page loaded from cache': return '页面已从缓存加载';
    case 'Page loaded from local cache': return '页面已从本地缓存加载';
    case 'Page loaded from downloads': return '页面已从下载文件加载';
    case 'Page URL is unavailable': return '页面 URL 不可用';
    case 'Image download failed': return '图片下载失败';
    case 'Network request failed': return '网络请求失败';
    case 'Cannot parse sign in response': return '无法解析登录响应';
    case 'Captcha required; use Cookie sign in or web login later': return '需要验证码，请使用 Cookie 登录或稍后通过网页登录';
    case 'Tag is empty': return '标签为空';
    case 'Donate entry is retained from the original app; payment integration is not migrated yet.': return '保留了原应用的捐赠入口，支付功能尚未移植。';
    case 'EhViewer archive download': return 'EhViewer 存档下载';
    case 'EhViewer download': return 'EhViewer 下载';
    case 'Privacy mode disabled': return '隐私模式已关闭';
    case 'unknown error': return '未知错误';
    case 'Gallery Toplists': return '画廊排行榜';
    case 'Uploader Toplists': return '上传者排行榜';
    case 'Tagging Toplists': return '标签排行榜';
    case 'Hentai@Home Toplists': return 'Hentai@Home 排行榜';
    case 'EHTracker Toplists': return 'EHTracker 排行榜';
    case 'Cleanup Toplists': return '清理排行榜';
    case 'Rating&Reviewing Toplists': return '评分与审核排行榜';
    case 'All Time': return '全部时间';
    case 'Past Year': return '过去一年';
    case 'Past Month': return '过去一个月';
    case 'Yesterday': return '昨天';
    case 'History deleted': return '历史记录已删除';
    case 'Loading top lists...': return '正在加载排行榜...';
    case 'No image selected for search': return '未选择用于搜索的图片';
    case 'Tap a ranking item to load detail': return '点击排行条目加载详情';
    case 'Core models and URL builders': return '核心模型与 URL 构建器';
    case 'Network session and cookies': return '网络会话与 Cookie';
    case 'HTML and API parsers': return 'HTML 与 API 解析器';
    case 'Gallery list and detail UI': return '画廊列表与详情界面';
    case 'Settings hierarchy': return '设置层级';
    case 'Reader and image pipeline': return '阅读器与图片管线';
    case 'Downloads and storage': return '下载与存储';
    case 'app/src/main/java/com/hippo/ehviewer/client/data': return 'app/src/main/java/com/hippo/ehviewer/client/data';
    case 'entry/src/main/ets/model': return 'entry/src/main/ets/model';
    case 'EhEngine, EhRequest, OkHttp helpers': return 'EhEngine、EhRequest、OkHttp 辅助代码';
    case 'HarmonyOS HTTP service': return 'HarmonyOS HTTP 服务';
    case 'client/parser': return 'client/parser';
    case 'ArkTS parser services': return 'ArkTS 解析服务';
    case 'ui/scene/gallery': return 'ui/scene/gallery';
    case 'ArkUI pages and components': return 'ArkUI 页面与组件';
    case 'SettingsActivity and res/xml/*_settings.xml': return 'SettingsActivity 与 res/xml/*_settings.xml';
    case 'ArkUI SettingsScene': return 'ArkUI SettingsScene';
    case 'glgallery, glview, native image code': return 'glgallery、glview 与原生图片代码';
    case 'ArkUI reader plus native image bridge': return 'ArkUI 阅读器与原生图片桥接';
    case 'HistoryScene, EhDB history DAO': return 'HistoryScene 与 EhDB 历史 DAO';
    case 'ArkUI HistoryScene and HarmonyOS preferences store': return 'ArkUI HistoryScene 与 HarmonyOS 首选项存储';
    case 'download service and FileProvider': return '下载服务与 FileProvider';
    case 'HarmonyOS background task and file APIs': return 'HarmonyOS 后台任务与文件 API';
    case 'started: models, EhUrl, list/favorites URL builders': return '进行中：模型、EhUrl、列表/收藏 URL 构建器';
    case 'started: GET/POST client, password/Web/Cookie sign-in, persistent Cookie store, referer-aware loads, duplicate request coalescing, bounded text request pool, transient failure retry, per-call cache-control, system/custom proxy, DoH and built-in host rules, friendly HTTP/network diagnostics, short shared response cache, persisted SpiderInfo showKey cache and showpage API fast path': return '进行中：GET/POST 客户端、密码/网页/Cookie 登录、持久化 Cookie、Referer 请求、重复请求合并、请求池、失败重试、缓存控制、代理、DoH、内置 hosts、网络诊断、共享响应缓存及 showpage API 快速路径';
    case 'started: GalleryListParser, GalleryDetailParser, GalleryPageParser and TopListParser': return '进行中：GalleryListParser、GalleryDetailParser、GalleryPageParser 与 TopListParser';
    case 'started: Android-style drawer hierarchy, settings-hosted sign-in flows, list/detail scenes, top-list scene, action-card header controls; GalleryCommentsScene implemented with HTML stripping, comment previews in detail page and full CommentsScene navigation in GalleryListScene/HistoryScene/TopListScene': return '进行中：Android 风格抽屉、设置内登录流程、列表/详情/排行场景和操作卡片；已实现评论 HTML 清理、详情评论预览及完整评论页面导航';
    case 'started: drawer matches Android nav_drawer_main; all setting panels implemented; UConfig/MyTags open in embedded WebView; Filter rules managed via EhFilterStore with local preferences persistence and applied to gallery list; Export/Import data via DocumentViewPicker (cookies, settings, history, downloads, filters bundled to JSON); Identity authentication via userIAM.userAuth biometric/PIN prompt on app foreground': return '进行中：抽屉匹配 Android nav_drawer_main；已实现全部设置面板、UConfig/MyTags、过滤规则、数据导入导出及身份验证';
    case 'started: GalleryPageParser, showpage API parser, preview-to-reader entry, previous/next, retry, zoom, fit mode, original-image toggle, info panel, first-page warmup, page cache, in-flight page coalescing, previous-page referer handoff, reader/thumb image file cache, prioritized three-slot image queue, configurable image timeout, transient image retry, partial-file cleanup, sequential adjacent preload and reading-direction tap zones': return '进行中：页面解析、showpage API、阅读入口、翻页、重试、缩放、适配模式、原图切换、信息面板、预热、缓存、请求合并、Referer 传递、图片队列、超时重试、残留清理、相邻页预载及阅读方向点击区域';
    case 'started: viewed gallery details are persisted, listed, reopened, removed and cleared': return '进行中：已支持浏览历史的持久化、列表显示、重新打开、删除与清空';
    case 'started: preferences-backed download queue and labels, detail-page enqueue/remove, Downloads scene, search, status/label filters, sorting, foreground queue runner, resume existing page files, page/image fetch progress, app-files gallery folder output, start/stop-all state transitions and finished cleanup': return '进行中：已支持持久化下载队列与标签、详情页加入/移除、下载页面、搜索过滤排序、前台队列、断点续传、进度显示、画廊目录输出、批量启停与完成项清理';
    case 'Signing in...': return '正在登录...';
    default: return text;
  }
}

let activeBackHandler: (() => boolean) | null = null;
let readerActiveBackHandler: (() => boolean) | null = null;
const DETAIL_BACK_HANDLERS: Array<() => boolean> = [];

export function setActiveBackHandler(handler: (() => boolean) | null): void {
  activeBackHandler = handler;
}

export function runActiveBackHandler(): boolean {
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

export function toggleGalleryDownload(gallery: GalleryInfo): boolean {
  if (ehDownloadStore.contains(gallery.gid)) {
    ehDownloadStore.removeGallery(gallery.gid);
    saveDownloadsQuietly();
    return false;
  }

  const item = ehDownloadStore.addGallery(gallery, '');
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

export function filterDownloadItems(items: DownloadInfo[], query: string, statusFilter: string, labelFilter: string,
  sortMode: string, categoryFilter: string = 'All'): DownloadInfo[] {
  const normalizedQuery = query.toLowerCase().trim();
  const filtered: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const stateLabel = downloadStateLabel(item.state);
    const statusMatched = statusFilter === 'All' || stateLabel === statusFilter ||
      (statusFilter === 'Downloading' && stateLabel === 'Waiting');
    if (!statusMatched) {
      continue;
    }
    if (labelFilter !== 'All' && downloadLabelName(item.label) !== labelFilter) {
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
  const options: string[] = ['All', 'Idle', 'Waiting', 'Downloading', 'Downloaded', 'Failed'];
  return nextStringOption(current, options);
}

export function nextDownloadLabelFilter(current: string, labels: DownloadLabel[]): string {
  const options: string[] = ['All', 'Default'];
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

function downloadLabelName(label: string): string {
  return label.length === 0 ? 'Default' : label;
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

const APP_THEME_COLOR: string = EH_THEME_PRIMARY_COLOR;

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
  const source = from.length >= 7 && from.charAt(0) === '#' ? from : APP_THEME_COLOR;
  const target = to.length >= 7 && to.charAt(0) === '#' ? to : '#FFFFFF';
  const ratio = Math.max(0, Math.min(1, amount));
  const r = parseHexChannel(source, 1) + (parseHexChannel(target, 1) - parseHexChannel(source, 1)) * ratio;
  const g = parseHexChannel(source, 3) + (parseHexChannel(target, 3) - parseHexChannel(source, 3)) * ratio;
  const b = parseHexChannel(source, 5) + (parseHexChannel(target, 5) - parseHexChannel(source, 5)) * ratio;
  return '#' + hexChannel(r) + hexChannel(g) + hexChannel(b);
}

export function themeSurfaceColor(amount: number = 0.88): string {
  return mixHexColor(APP_THEME_COLOR, '#FFFFFF', amount);
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
  const value = Number.parseInt(ehSettingsStore.getValue('download_thread', '3'));
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
  let done = 0;
  let failed = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].state === DownloadState.Wait) {
      wait++;
    } else if (items[i].state === DownloadState.Downloading) {
      active++;
    } else if (items[i].state === DownloadState.Finish) {
      done++;
    } else if (items[i].state === DownloadState.Failed) {
      failed++;
    }
  }
  return uiText('Waiting') + ' ' + wait.toString() + ' / ' + uiText('Downloading') + ' ' + active.toString() +
    ' / ' + uiText('Downloaded') + ' ' + done.toString() + ' / ' + uiText('Failed') + ' ' + failed.toString();
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
  return 'Settings';
}

export function settingsRowsForPanel(panel: SettingsPanel, themeName: string, entries: SettingEntry[]): SettingsRowItem[] {
  if (panel === SettingsPanel.Eh) {
    const followSystemDarkMode = settingEntryValue(entries, 'follow_system_dark_mode', 'Off') === 'On';
    return [
      staticSettingsRow('identity_cookie', 'Identity cookies', 'View or import ipb_member_id, ipb_pass_hash and igneous', 'Session', 'action'),
      optionSettingsRow('gallery_site', 'Gallery site', 'Original setting chooses E-Hentai or ExHentai where supported', entries, ['E-Hentai', 'ExHentai']),
      staticSettingsRow('u_config', 'UConfig', 'Account configuration page, requires sign in', 'Open', 'action'),
      optionSettingsRow('use_account_default_filter', 'Use account filters', 'Use filtering options captured from UConfig', entries, ON_OFF_OPTIONS),
      staticSettingsRow('my_tags', 'My Tags', 'Manage watched and hidden tags, requires sign in', 'Open', 'action'),
      optionSettingsRow('launch_page', 'Launch page', 'Default start scene after warnings and sign-in checks', entries, ['Homepage', 'Subscription', 'What\'s Hot', 'Favorites']),
      optionSettingsRow('list_mode', 'List mode', 'Gallery list style from original Android preferences', entries, ['Detail', 'Thumb', 'Extended']),
      optionSettingsRow('detail_size', 'Detail size', 'Gallery detail image and metadata density', entries,
        ['Compact', 'Medium', 'Loose']),
      optionSettingsRow('thumb_size', 'Thumb size', 'Thumbnail size used in gallery rows', entries,
        ['Small', 'Medium', 'Large', 'XLarge']),
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
          'Original app cycles Light, Dark and Black from drawer/footer and Settings',
        entries, followSystemDarkMode ? ['Dark', 'Black'] : ['Light', 'Dark', 'Black']),
      staticSettingsRow('filter', 'Filter', 'Keyword/gallery filtering rules', 'Open', 'action'),
      optionSettingsRow('show_eh_limits', 'Show EH limits', 'Display account and image limits in the drawer', entries, ON_OFF_OPTIONS),
      optionSettingsRow('cellular_network_warning', 'Cellular network warning', 'Warn before network-heavy operations on mobile data', entries, ON_OFF_OPTIONS)
    ];
  }

  if (panel === SettingsPanel.Read) {
    const readingDirection = normalizeReadingDirectionOption(settingEntryValue(entries, 'reading_direction', 'Right to left'));
    const continuousMode = readingDirection === 'Top to bottom';
    return [
      optionSettingsRow('screen_rotation', 'Screen rotation', 'Reader orientation policy', entries,
        continuousMode ? ['Default', 'Portrait', 'Landscape', 'Auto rotate'] :
          ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image']),
      optionSettingsRow('reading_direction', 'Reading direction', 'Left-to-right, right-to-left or vertical reader movement', entries, ['Left to right', 'Right to left', 'Top to bottom']),
      optionSettingsRow('page_scaling', 'Page scaling', 'Fit width, fit height or original page scaling', entries,
        continuousMode ? ['Actual size', 'Fit width', 'Fixed scale'] :
          ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale']),
      optionSettingsRow('start_position', 'Start position', 'Where a gallery starts when opened', entries, ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center']),
      optionSettingsRow('start_transfer_time', 'Auto transfer time', 'Automatic next-page delay from original seekbar preference', entries, readerAutoTransferTimeOptions()),
      optionSettingsRow('reader_standalone', 'Standalone reader', 'Open reader in a standalone ability', entries, ON_OFF_OPTIONS),
      optionSettingsRow('keep_screen_on', 'Keep screen on', 'Prevent screen sleep while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_clock', 'Show clock', 'Show clock overlay in the reader', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_progress', 'Show progress', 'Show reader progress overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_battery', 'Show battery', 'Show battery overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('volume_page', 'Volume page', 'Use volume buttons to turn pages', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reading_fullscreen', 'Reading fullscreen', 'Hide system chrome while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reader_background', 'Reader background', 'Background color behind reader pages', entries, ['Black', 'White', 'Deep gray']),
      optionSettingsRow('custom_screen_lightness', 'Custom brightness', 'Enable custom reader brightness', entries, ON_OFF_OPTIONS),
      optionSettingsRow('screen_lightness', 'Screen lightness', 'Custom reader brightness when enabled', entries, readerBrightnessLevelOptions()),
      optionSettingsRow('ultra_dark_mode', 'Ultra dark mode', 'Dim reader with a black overlay and minimum system brightness', entries, ON_OFF_OPTIONS),
      optionSettingsRow('ultra_dark_lightness', 'Ultra dark brightness', 'Black overlay opacity while ultra dark mode is enabled', entries, readerUltraDarkLightnessOptions())
    ];
  }

  if (panel === SettingsPanel.Download) {
    return [
      optionSettingsRow('download_location', 'Download location', 'App internal storage or public Downloads directory', entries, ['App files', 'Downloads']),
      optionSettingsRow('download_thread', 'Multi-thread download', 'Number of images downloaded at the same time',
        entries, ['1', '2', '3', '4', '5', '8', '10']),
      optionSettingsRow('preload_image', 'Preload image', 'Reader/download prefetch count', entries, ['0', '3', '5', '10', '20']),
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

  if (panel === SettingsPanel.Advanced) {
    const rows: SettingsRowItem[] = [
      staticSettingsRow('dump_logcat', 'Export log', 'Save the local app log to a text file', 'Export', 'action'),
      staticSettingsRow('clear_download_path_cache', 'Clear download path cache', 'Refresh cached file path and size lookups', 'Run', 'action'),
      staticSettingsRow('clear_memory_cache', 'Clear cache', 'Drop reader image and page caches',
        currentReaderCacheSizeText(), 'action'),
      optionSettingsRow('read_cache_size', 'Read cache size', 'Reader cache budget', entries,
        ['160 MB', '320 MB', '640 MB', '1 GB', '2 GB']),
      optionSettingsRow('app_language', 'App language', 'Language override', entries, ['System', 'English', 'zh-CN']),
      optionSettingsRow('proxy', 'Proxy', 'System proxy, direct connection or HTTP proxy', entries, ['System', 'Off', 'HTTP']),
      staticSettingsRow('network_diagnostics', 'Network diagnostics', 'Test E, EX, forums and repo connectivity with current settings', 'Run', 'action'),
    ];
    const proxyType = settingEntryValue(entries, 'proxy', 'System');
    if (proxyType === 'HTTP' || proxyType === 'SOCKS') {
      rows.push(textSettingsRow('proxy_host', 'Proxy host', 'Host or IP address for HTTP proxy', entries, '127.0.0.1'));
      rows.push(textSettingsRow('proxy_port', 'Proxy port', '1-65535', entries, '8080'));
      rows.push(textSettingsRow('proxy_username', 'Proxy username', 'Optional proxy authentication username', entries, ''));
      rows.push(textSettingsRow('proxy_password', 'Proxy password', 'Optional proxy authentication password', entries, ''));
      rows.push(textSettingsRow('proxy_exclusion_list', 'Proxy exclusions', 'Comma-separated hosts that should bypass the proxy', entries, 'localhost,127.0.0.1'));
    }
    rows.push(optionSettingsRow('built_in_hosts', 'Built-in hosts', 'Force bundled host overrides; leave Off for normal Cloudflare DNS', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('built_ex_hosts', 'Built EX hosts', 'Force bundled ExHentai host overrides; leave Off unless your network needs them', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('dns_over_https', 'Secure DNS (DoH)', 'Resolve DNS pollution in some regions',
      entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('domain_fronting', 'Domain fronting', 'Bypass SNI blocking using built-in host fronting', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('auto_direct_connection', 'Direct connection check', 'Use direct connection when the selected site responds within 5s', entries, ON_OFF_OPTIONS));
    rows.push(staticSettingsRow('export_data', 'Export data', 'Save settings, history, downloads and filter rules to a JSON file', 'Export', 'action'));
    rows.push(staticSettingsRow('import_data', 'Import data', 'Restore from a JSON backup or Android exported database', 'Import', 'action'));
    rows.push(staticSettingsRow('wifi_transfer', 'Wi-Fi server/client', 'Original Wi-Fi transfer tools', 'Not migrated', 'activity'));
    return rows;
  }

  if (panel === SettingsPanel.About) {
    return [
      staticSettingsRow('declaration', 'Declaration', 'Current HarmonyOS repository', 'Info', 'message'),
      staticSettingsRow('author', 'Author', EH_AUTHOR_NAME, 'GitHub', 'url'),
      staticSettingsRow('latest_release', 'Version', 'GitHub release for the current port', EH_RELEASE_TAG, 'url'),
      staticSettingsRow('issue_help', 'Issue help', 'Issue tracker for the current port', 'Issues', 'url'),
      staticSettingsRow('license', 'License', 'Inherited from original app', 'GPL-3.0', 'url'),
      staticSettingsRow('check_for_updates', 'Check for updates', 'Check the latest GitHub release', 'Run', 'action'),
      optionSettingsRow('close_auto_updates', 'Close automatic updates', 'Disable startup update check', entries, ON_OFF_OPTIONS),
      staticSettingsRow('donate', 'Donate', 'Original donation entry', 'Not migrated', 'url')
    ];
  }

  return [staticSettingsRow('theme', 'Theme', 'Current staged theme', themeName, 'list')];
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

function optionSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], options: string[]): SettingsRowItem {
  let rawValue = settingEntryValue(entries, key, options.length > 0 ? options[0] : '');
  if (key === 'theme' && options.length > 0 && options.indexOf(rawValue) < 0) {
    rawValue = options[0];
  }
  const sliderRow = key === 'start_transfer_time' || key === 'screen_lightness' || key === 'ultra_dark_lightness';
  return {
    key: key,
    title: title,
    summary: summary,
    value: normalizeReaderSettingOption(key, rawValue),
    type: sliderRow ? 'slider' : options.length === 2 && options[0] === 'On' && options[1] === 'Off' ? 'switch' : 'list',
    options: options
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
  return 'Top right';
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

export function settingMigrationMessage(key: string): string {
  if (key === 'u_config') {
    return 'UConfig requires the account configuration parser and editor. The sign-in/session part is already available.';
  }
  if (key === 'my_tags') {
    return 'My Tags opens the native watched and hidden tag editor.';
  }
  if (key === 'filter') {
    return 'Filter rules need the local rule database before they can hide galleries in list scenes.';
  }
  if (key === 'pattern_protection') {
    return 'Identity authentication uses HarmonyOS biometric, face or PIN verification.';
  }
  if (key === 'export_data') {
    return 'Export data needs a backup bundle writer for settings, cookies, downloads and history.';
  }
  if (key === 'import_data') {
    return 'Import data needs the matching backup reader before it can safely replace local state.';
  }
  if (key === 'wifi_transfer') {
    return 'Wi-Fi transfer needs a HarmonyOS local server/client implementation.';
  }
  return 'This original app entry has not been migrated yet.';
}

export function isValidProxyPortText(value: string): boolean {
  const port = Number.parseInt(value);
  return !Number.isNaN(port) && port > 0 && port <= 65535 && port.toString() === value.trim();
}

export function normalizeProxyOption(value: string): string {
  if (value === 'Off' || value === 'HTTP') {
    return value;
  }
  if (value === 'SOCKS') {
    return 'HTTP';
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
  gallery?: GalleryInfo, index?: number, abilityContext?: common.UIAbilityContext, onError?: (message: string) => void): void {
  const context = abilityContext !== undefined ? abilityContext : getAbilityContext();
  if (context === undefined) {
    if (onError !== undefined) {
      onError('Ability context is not ready');
    }
    return;
  }

  if (gallery !== undefined && index !== undefined) {
    const downloadedPath = ehDownloadFileStore.findPageImage(context, gallery, index);
    if (downloadedPath.length > 0) {
      onReady(cloneGalleryPageWithCache(page, downloadedPath));
      return;
    }
  }

  if (page.imageUrl.length === 0) {
    if (onError !== undefined) {
      onError('Image URL missing');
    }
    return;
  }

  const existing = readerImageCache.getCachedPath(context, page.imageUrl, readerPageImageCacheKey(page, false));
  if (existing.length > 0) {
    onReady(cloneGalleryPageWithCache(page, existing));
    return;
  }

  readerImageCache.ensureCached(context, page.imageUrl, page.pageUrl, true, undefined,
    readerPageImageCacheKey(page, false)).then((path: string) => {
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
    for (let i = 0; i < count; i++) {
      const item = THUMBNAIL_READY_QUEUE.shift();
      if (item !== undefined) {
        try {
          item.onReady(item.path);
        } catch (error) {
        }
      }
    }
    if (THUMBNAIL_READY_QUEUE.length > 0) {
      scheduleThumbnailReadyDelivery();
    }
  }, THUMBNAIL_READY_BATCH_DELAY_MS);
}

export function cacheThumbnailImage(url: string, onReady: (path: string) => void, onError?: () => void): void {
  const context = getAbilityContext();
  if (context === undefined || url.length === 0) {
    if (onError !== undefined) {
      onError();
    }
    return;
  }

  const existing = readerImageCache.getCachedPath(context, url);
  if (existing.length > 0) {
    enqueueThumbnailReady(existing, onReady);
    return;
  }

  readerImageCache.ensureCached(context, url, EhUrl.getReferer(currentGallerySite()), false, undefined, '',
    { retryLimit: THUMBNAIL_RETRY_LIMIT }).then((path: string) => {
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
    return gallery.titleJpn;
  }
  if (gallery.title.length > 0) {
    return gallery.title;
  }
  if (gallery.titleJpn !== undefined && gallery.titleJpn.length > 0) {
    return gallery.titleJpn;
  }
  return 'Untitled';
}

export function showGalleryPages(): boolean {
  return ehSettingsStore.getValue('show_gallery_pages', 'Off') === 'On';
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

export function galleryThumbHeight(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Medium');
  if (value === 'Small') {
    return 96;
  }
  if (value === 'Large') {
    return 142;
  }
  if (value === 'XLarge') {
    return 170;
  }
  return 118;
}

export function detailTitleFontSize(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  if (value === 'Compact') {
    return 16;
  }
  if (value === 'Large' || value === 'Loose') {
    return 20;
  }
  return 18;
}

export function detailTitleMaxLines(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Medium');
  if (value === 'Compact') {
    return 3;
  }
  if (value === 'Large' || value === 'Loose') {
    return 6;
  }
  return 5;
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

export function topListChipColor(index: number): string {
  const colors: string[] = ['#2F6F8F', '#7A5A22', '#327A5B', '#A04462', '#4D6D8C', '#805A8F', '#8A4F2B', '#556B2F', '#6B7280', '#1F6B63'];
  return colors[index % colors.length];
}
