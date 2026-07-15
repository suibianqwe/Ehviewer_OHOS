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
  findSavedTranslationApi,
  parseSavedTranslationApis
} from '../services/TranslationApiConfigSupport';
import { decodeHtmlEntities } from './HtmlEntitySupport';
import { traditionalChineseText } from './EhTraditionalChinese';
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
  Advanced = 'advanced',
  WifiTransfer = 'wifi_transfer',
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
  { panel: SettingsPanel.Translation, title: 'Translation', icon: 'T', summary: 'Title and comment translation providers' },
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
  return currentUiLanguage() !== 'English';
}

export function shouldShowTagTranslations(): boolean {
  return ehSettingsStore.getValue('show_tag_translations', 'On') === 'On';
}

function currentUiLanguage(): string {
  const language = ehSettingsStore.getValue('app_language', 'System');
  if (language === 'zh-CN' || language === 'zh-TW' || language === 'English') {
    return language;
  }
  try {
    const systemLanguage = i18n.System.getSimplifiedLanguage();
    const supportedLanguages: Array<string> = ['zh-Hans', 'zh-Hant'];
    const matchedLanguage = i18n.I18NUtil.getBestMatchLocale(systemLanguage, supportedLanguages);
    if (matchedLanguage === 'zh-Hans') {
      return 'zh-CN';
    }
    if (matchedLanguage === 'zh-Hant') {
      return 'zh-TW';
    }
  } catch (error) {
  }
  return 'English';
}

function localizedChineseText(text: string): string {
  return currentUiLanguage() === 'zh-TW' ? traditionalChineseText(text) : text;
}

export function uiText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  return localizedChineseText(zhText(text));
}

export function uiValue(value: string): string {
  return uiText(value);
}

export function plainTextFromHtml(html: string): string {
  return decodeHtmlEntities(html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<[^>]+>/g, ''))
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function uiStatusText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  return localizedChineseText(simplifiedUiStatusText(text));
}

function simplifiedUiStatusText(text: string): string {
  const deleteDownloadsMatch = /^Delete (\d+) selected downloads and their files\?$/.exec(text);
  if (deleteDownloadsMatch !== null) {
    return '将删除选中的 ' + deleteDownloadsMatch[1] + ' 个下载项及其文件，是否继续？';
  }
  if (text.indexOf('Wi-Fi server error: ') === 0) {
    return 'Wi-Fi 服务器错误：' + text.substring('Wi-Fi server error: '.length);
  }
  if (text.indexOf('Unable to start Wi-Fi server: ') === 0) {
    return '无法启动 Wi-Fi 服务器：' + text.substring('Unable to start Wi-Fi server: '.length);
  }
  if (text.indexOf('Wi-Fi client error: ') === 0) {
    return 'Wi-Fi 客户端错误：' + text.substring('Wi-Fi client error: '.length);
  }
  if (text.indexOf('Unable to connect: ') === 0) {
    return '连接失败：' + text.substring('Unable to connect: '.length);
  }
  if (text.indexOf('Device connection error: ') === 0) {
    return '设备连接错误：' + text.substring('Device connection error: '.length);
  }
  if (text.indexOf('Wi-Fi Direct connection failed: ') === 0) {
    return 'Wi-Fi 直连失败：' + text.substring('Wi-Fi Direct connection failed: '.length);
  }
  if (text.indexOf('Unable to connect with Wi-Fi Direct: ') === 0) {
    return '无法通过 Wi-Fi 直连连接：' + text.substring('Unable to connect with Wi-Fi Direct: '.length);
  }
  if (text.indexOf('Send failed: ') === 0) {
    return '发送失败：' + text.substring('Send failed: '.length);
  }
  if (text.indexOf('Received data is invalid: ') === 0) {
    return '接收的数据无效：' + text.substring('Received data is invalid: '.length);
  }
  if (text.indexOf('Transfer completed: ') === 0) {
    return '传输完成：' + text.substring('Transfer completed: '.length).replace(' items', ' 项');
  }
  if (text.indexOf('Received and saved: ') === 0) {
    return '已接收并保存：' + text.substring('Received and saved: '.length).replace(' items', ' 项');
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
  if (text === 'Enter ipb_member_id, ipb_pass_hash and optional igneous') {
    return '输入 ipb_member_id、ipb_pass_hash 和可选的 igneous';
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
  if (text.indexOf('Restored galleries: ') >= 0 || text.indexOf('ZIP archives processed: ') >= 0 ||
      text.indexOf('Unprocessed ZIP archives: ') >= 0) {
    return text.replace('Restored galleries: ', '已恢复画廊：')
      .replace('ZIP archives processed: ', '已处理压缩包：')
      .replace(', skipped: ', '，已跳过：')
      .replace('Unprocessed ZIP archives: ', '未处理压缩包：')
      .replace('. Downloads access was not granted; scanned app files only', '。未授权访问下载目录，仅扫描应用文件')
      .replace('. ', '。');
  }
  if (text === 'No downloaded galleries found') {
    return '未找到可恢复的画廊';
  }
  if (text.indexOf('ZIP import summary: processed ') === 0) {
    return text.replace('ZIP import summary: processed ', '已处理压缩包 ')
      .replace(', skipped ', ' 个，已跳过 ')
      .replace('. Delete processed archives?', ' 个。是否删除已处理的压缩包？');
  }
  if (text.indexOf('Deleted processed ZIP archives: ') === 0) {
    return '已删除压缩包：' + text.substring('Deleted processed ZIP archives: '.length);
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
  const modelCountMatch = /^Available models loaded: (\d+)$/.exec(text);
  if (modelCountMatch !== null) {
    return '已获取 ' + modelCountMatch[1] + ' 个可用模型';
  }
  const composite = translateCompositeUiStatus(text);
  if (composite !== text) {
    return composite;
  }
  return zhText(text);
}

interface UiStatusPrefixTranslation {
  source: string;
  target: string;
}

const UI_STATUS_PREFIX_TRANSLATIONS: UiStatusPrefixTranslation[] = [
  { source: 'Archive failed: ', target: '存档失败：' },
  { source: 'Available models could not be loaded: ', target: '无法获取可用模型：' },
  { source: 'Model list request failed: ', target: '模型列表获取失败：' },
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
  { source: 'Tag translation database updated: ', target: '标签翻译数据库已更新：' },
  { source: 'Tag translation database update failed: ', target: '标签翻译数据库更新失败：' },
  { source: 'database save failed: ', target: '数据库保存失败：' },
  { source: 'create database directory failed: ', target: '创建数据库目录失败：' },
  { source: 'write database file failed: ', target: '写入数据库文件失败：' },
  { source: 'replace database file failed: ', target: '替换数据库文件失败：' },
  { source: 'Tag vote failed: ', target: '标签投票失败：' },
  { source: 'Torrent failed: ', target: '种子加载失败：' },
  { source: 'Translation failed: ', target: '翻译失败：' },
  { source: 'Youdao web translation failed: ', target: '有道网页翻译失败：' },
  { source: 'Created API: ', target: '已新建 API：' },
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
  { source: ' tags', target: ' 个标签' },
  { source: ' failed', target: ' 失败' }
];

function translateCompositeUiStatus(text: string): string {
  let translated = text;
  for (let i = 0; i < UI_STATUS_PREFIX_TRANSLATIONS.length; i++) {
    const item = UI_STATUS_PREFIX_TRANSLATIONS[i];
    if (text.startsWith(item.source)) {
      const remainder = text.substring(item.source.length);
      const nested = translateCompositeUiStatus(remainder);
      translated = item.target + (nested === remainder ? zhText(remainder) : nested);
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
  return shouldUseChineseUi() ? localizedChineseText(prefix + page.toString() + ' 页') : prefix + page.toString();
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
    case 'Remove from favorites': return '移出收藏';
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
    case 'Translation': return '翻译';
    case 'Title and comment translation providers': return '标题与评论翻译服务';
    case 'Translation feature': return '翻译功能';
    case 'Show translation buttons on gallery lists, details and comments': return '在画廊列表、详情和评论中显示翻译按钮';
    case 'The translation toggle is in the lower-right toolbar': return '翻译开关在右下角工具栏中';
    case 'Translation provider': return '翻译服务';
    case 'Choose a web translation or AI translation service': return '选择网页翻译或 AI 翻译服务';
    case 'Machine translation': return '普通机翻';
    case 'Machine translation provider': return '普通机翻服务';
    case 'Choose a web translation service used when AI translation is off': return '选择关闭 AI 翻译时使用的网页翻译服务';
    case 'Choose the web translation service': return '选择网页翻译服务';
    case 'Merge translation requests': return '合并翻译请求';
    case 'Combine pending texts into fewer requests; AI batches contain up to 5 texts': return '合并待翻译文本以减少请求；AI 每批最多合并 5 条';
    case 'AI translation': return 'AI 翻译';
    case 'AI translation service': return 'AI 翻译服务';
    case 'Choose the AI translation service': return '选择 AI 翻译服务';
    case 'Use the selected AI service instead of ordinary machine translation': return '使用所选 AI 服务代替普通机翻';
    case 'AI translation provider': return 'AI 翻译服务';
    case 'Choose the AI service used while AI translation is enabled': return '选择启用 AI 翻译时使用的服务';
    case 'Record AI conversations': return '记录 AI 翻译对话';
    case 'Save prompts sent to AI services and their returned text locally; disabling clears all records': return '在本机记录发送给 AI 的提示词及其返回内容；关闭时清空全部记录';
    case 'Export AI conversation records': return '导出 AI 翻译记录';
    case 'Export recorded AI translation conversations to public Downloads': return '将记录的 AI 翻译对话导出到公共下载目录';
    case 'No AI translation records yet': return '暂无 AI 翻译记录';
    case 'AI translation records exported': return 'AI 翻译记录已导出';
    case 'AI translation record export needs an ability context': return '导出 AI 翻译记录需要应用上下文';
    case 'AI translation record export failed': return 'AI 翻译记录导出失败';
    case 'System prompts': return '系统提示词';
    case 'Choose, edit and save prompts used by AI translation': return '选择、编辑并保存 AI 翻译使用的提示词';
    case 'Prompt preset': return '提示词预设';
    case 'Built-in presets and saved custom prompts': return '内置预设与已保存的自定义提示词';
    case 'Prompt name': return '提示词名称';
    case 'Name used in the prompt list': return '在提示词列表中显示的名称';
    case 'System prompt': return '系统提示词';
    case 'Instructions sent to the AI translation service': return '发送给 AI 翻译服务的固定指令';
    case 'New prompt': return '新建提示词';
    case 'Create a custom prompt from the current content': return '以当前内容新建自定义提示词';
    case 'Prompt saved': return '提示词已保存';
    case 'Prompt selected': return '已切换提示词';
    case 'Prompt deleted': return '提示词已删除';
    case 'Built-in preset': return '内置预设';
    case 'Prompt name and content are required': return '提示词名称和内容不能为空';
    case 'Built-in presets are read-only; saving creates a custom copy': return '内置预设不可覆盖，保存时会创建自定义副本';
    case 'Faithful': return '完整忠实';
    case 'Strict brackets': return '严格括号';
    case 'Natural localization': return '自然润色';
    case 'Token saving': return '省 Token';
    case 'Custom prompt': return '自定义提示词';
    case 'Free Google web translation without an API key': return '无需密钥的免费 Google 网页翻译';
    case 'Free Microsoft web translation without an API key': return '无需密钥的免费微软网页翻译';
    case 'Free Baidu web translation without an API key': return '无需密钥的免费百度网页翻译';
    case 'Free Youdao web translation without an API key': return '无需密钥的免费有道网页翻译';
    case 'Public translation memory with a short text limit': return '有短文本限制的公共翻译记忆库';
    case 'Open-source Google translation proxy': return '开源 Google 翻译代理';
    case 'DeepSeek AI translation using your API key': return '使用个人密钥的 DeepSeek AI 翻译';
    case 'OpenAI model translation using your API key': return '使用个人密钥的 OpenAI 模型翻译';
    case 'Google Gemini translation using your API key': return '使用个人密钥的 Google Gemini 翻译';
    case 'Saved OpenAI-compatible APIs and local model services': return '已保存的 OpenAI 兼容接口和本地模型服务';
    case 'Target language': return '目标语言';
    case 'Language used for gallery titles and comments': return '画廊标题与评论使用的翻译语言';
    case 'Translation timeout': return '翻译超时';
    case 'Maximum wait time for a translation request': return '单次翻译请求的最长等待时间';
    case 'DeepSeek API key': return 'DeepSeek API 密钥';
    case 'Stored locally and sent only to DeepSeek': return '仅保存在本机，并只发送给 DeepSeek';
    case 'DeepSeek model': return 'DeepSeek 模型';
    case 'Fetch available models or enter a model name': return '自动获取可用模型，或手动输入模型名称';
    case 'OpenAI API key': return 'OpenAI API 密钥';
    case 'Stored locally and sent only to OpenAI': return '仅保存在本机，并只发送给 OpenAI';
    case 'OpenAI model': return 'OpenAI 模型';
    case 'Fetch available OpenAI models or enter a model name': return '自动获取可用的 OpenAI 模型，或手动输入名称';
    case 'API base URL': return 'API 基础地址';
    case 'Base URL ending in /v1, or a complete /chat/completions URL': return '以 /v1 结尾的基础地址，或完整的 /chat/completions 地址';
    case 'API key': return 'API 密钥';
    case 'Stored locally and sent only to the configured API endpoint': return '仅保存在本机，并只发送给所配置的 API 地址';
    case 'Model': return '模型';
    case 'Model name supported by the configured endpoint': return '所配置接口支持的模型名称';
    case 'Gemini API key': return 'Gemini API 密钥';
    case 'Stored locally and sent only to Google Gemini': return '仅保存在本机，并只发送给 Google Gemini';
    case 'Gemini model': return 'Gemini 模型';
    case 'Fetch available Gemini models or enter a model name': return '自动获取可用的 Gemini 模型，或手动输入名称';
    case 'Saved API': return '已保存的 API';
    case 'Choose a saved API or create a new configuration': return '选择已保存的 API，或新建配置';
    case 'New...': return '新建…';
    case 'API name': return 'API 名称';
    case 'Name shown in the saved API list': return '在已保存 API 列表中显示的名称';
    case 'API address': return 'API 地址';
    case 'Base URL ending in /v1 or a complete chat completions URL': return '以 /v1 结尾的基础地址，或完整的聊天补全地址';
    case 'Stored separately for this saved API': return '为当前已保存 API 单独存储';
    case 'Fetch models from this API or enter a model name': return '从当前 API 获取模型，或手动输入模型名称';
    case 'Public translation notice': return '公共翻译服务说明';
    case 'Public providers require no token but may be rate-limited or unavailable; translated text is sent to the selected service': return '公共服务无需密钥，但可能限流或不可用；待翻译文字会发送给所选服务';
    case 'Experimental': return '实验性';
    case 'Public service': return '公共服务';
    case 'Simplified Chinese': return '简体中文';
    case 'Traditional Chinese': return '繁体中文';
    case 'Japanese': return '日语';
    case 'Korean': return '韩语';
    case 'OpenAI': return 'OpenAI';
    case 'Custom API': return '自定义 API';
    case 'Google Web': return 'Google 网页';
    case 'Bing Web': return '必应网页';
    case 'Baidu Web': return '百度网页';
    case 'Youdao Web': return '有道网页';
    case 'Use custom value': return '使用自定义值';
    case 'Enter a model name': return '输入模型名称';
    case 'Loading available models...': return '正在获取可用模型…';
    case 'Available models could not be loaded': return '无法获取可用模型';
    case 'Translation timed out': return '翻译超时';
    case 'Translation API key is missing': return '未填写翻译 API 密钥';
    case 'Translation model is missing': return '未选择翻译模型';
    case 'No custom translation API is selected': return '未选择自定义翻译 API';
    case 'Invalid model list response': return '模型列表响应无效';
    case 'AI translation returned no content': return 'AI 翻译未返回内容';
    case 'AI translation response was truncated': return 'AI 翻译结果被截断';
    case 'AI translation response was incomplete': return 'AI 翻译结果不完整';
    case 'Bing web translation token is unavailable': return '无法获取必应网页翻译令牌';
    case 'Bing web translation is unavailable': return '必应网页翻译暂不可用';
    case 'Baidu web translation is unavailable': return '百度网页翻译暂不可用';
    case 'Invalid Baidu translation response': return '百度翻译响应无效';
    case 'Custom API saved': return '自定义 API 已保存';
    case 'Available models loaded': return '可用模型已加载';
    case 'No available models were returned': return '服务未返回可用模型';
    case 'Proxy settings saved': return '代理设置已保存';
    case 'SOCKS5 requires HarmonyOS API 26 or later': return 'SOCKS5 需要 HarmonyOS API 26 或更高版本';
    case 'Proxy host is required': return '代理主机不能为空';
    case 'Proxy port is invalid': return '代理端口无效';
    case 'Proxy type': return '代理类型';
    case 'Direct': return '直接连接';
    case 'Proxy host': return '代理主机';
    case 'Host or IP address': return '主机名或 IP 地址';
    case 'Proxy port': return '代理端口';
    case 'Proxy username': return '代理用户名';
    case 'Optional authentication username': return '可选的认证用户名';
    case 'Proxy password': return '代理密码';
    case 'Optional authentication password': return '可选的认证密码';
    case 'Proxy exclusions': return '代理排除列表';
    case 'Comma-separated hosts that bypass the proxy': return '使用英文逗号分隔不经过代理的主机';
    case 'SOCKS5 DNS': return 'SOCKS5 DNS';
    case 'Resolve target domains through the proxy': return '由代理服务器解析目标域名';
    case 'Resolve target domains through the system': return '由系统解析目标域名';
    case 'Save': return '保存';
    case 'Translate titles': return '翻译标题';
    case 'Show original titles': return '显示原标题';
    case 'Test translation': return '测试翻译';
    case 'Translate a short sample with the current provider': return '使用当前服务翻译一段简短示例';
    case 'Translation test succeeded': return '翻译测试成功';
    case 'Translation test failed': return '翻译测试失败';
    case 'Testing translation...': return '正在测试翻译...';
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
    case 'Scanning ZIP archives...': return '正在扫描压缩包...';
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
    case 'Keep': return '保留';
    case 'ZIP archives processed': return '压缩包处理完成';
    case 'New label': return '新标签';
    case 'All': return '全部';
    case 'Default': return '默认';
    case 'Idle': return '空闲';
    case 'Waiting': return '等待中';
    case 'Downloading': return '下载中';
    case 'Download completed': return '下载完成';
    case 'Download failed': return '下载失败';
    case 'Downloaded': return '已下载';
    case 'Failed': return '失败';
    case 'Updating': return '更新中';
    case 'Invalid': return '无效';
    case 'Status': return '状态';
    case 'Download status': return '下载状态';
    case 'Select statuses to display': return '选择要显示的下载状态';
    case 'Current status filter': return '当前状态筛选';
    case 'Sort': return '排序';
    case 'Selected': return '已选择';
    case 'Sign in': return '登录';
    case 'Sign out': return '退出登录';
    case 'The saved login session will be removed.': return '将清除已保存的登录会话，是否继续？';
    case 'Signed in': return '已登录';
    case 'Tourist': return '游客';
    case 'Guest mode': return '游客模式';
    case 'Register': return '注册';
    case 'Username': return '用户名';
    case 'Password': return '密码';
    case 'Sign in via WebView': return '通过网页登录';
    case 'Sign in via Cookies': return '通过 Cookie 登录';
    case 'Cookie Sign In': return 'Cookie 登录';
    case 'Web Sign In': return '网页登录';
    case 'Use this when password login needs captcha, or when importing an ExHentai session.': return '当密码登录需要验证码，或导入 ExHentai 会话时使用。';
    case 'Full Cookie header': return '完整 Cookie 头';
    case 'Clear': return '清除';
    case 'Clear Cookie': return '清除 Cookie';
    case 'Saved identity cookies and web cookies will be removed.': return '将清除已保存的身份 Cookie 和网页 Cookie，是否继续？';
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
    case 'Unavailable': return '暂不可用';
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
    case 'zh-TW': return '繁体中文';
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
    case 'Configure direct, system, HTTP or SOCKS5 proxy': return '配置直接连接、系统代理、HTTP 或 SOCKS5 代理';
    case 'Network diagnostics': return '网络诊断';
    case 'Built-in hosts': return '内置 hosts';
    case 'Built EX hosts': return '内置 EX hosts';
    case 'DNS over HTTPS': return 'DNS over HTTPS';
    case 'Secure DNS (DoH)': return '安全 DNS（DoH）';
    case 'DoH provider': return 'DoH 提供商';
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
    case 'Account session': return '账号会话';
    case 'Cookie session is available. Open to replace or inspect cookies.': return 'Cookie 会话可用。打开后可替换或查看 Cookie。';
    case 'Open password, WebView or Cookie sign-in and manage the current session.': return '使用密码、网页或 Cookie 登录并管理当前会话。';
    case 'Clear the persisted identity cookies': return '清除已保存的身份 Cookie';
    case 'Choose Light, Dark or Black for the app interface': return '选择应用界面的亮色、暗色或黑色主题';
    case 'Identity cookies': return '身份 Cookie';
    case 'View or import ipb_member_id, ipb_pass_hash and igneous': return '查看或导入 ipb_member_id、ipb_pass_hash 和 igneous';
    case 'Gallery site': return '画廊站点';
    case 'Select E-Hentai or ExHentai for browsing and requests': return '选择用于浏览和请求的 E-Hentai 或 ExHentai 站点';
    case 'Account configuration page, requires sign in': return '账号配置页面，需要登录';
    case 'Use account filters': return '使用账号过滤';
    case 'Use filtering options captured from UConfig': return '使用账号配置中抓取的过滤选项';
    case 'User tag set management, requires sign in': return '用户标签集管理，需要登录';
    case 'Manage watched and hidden tags, requires sign in': return '管理订阅和屏蔽标签，需要登录';
    case 'Launch page': return '启动页面';
    case 'Default start scene after warnings and sign-in checks': return '警告和登录检查后的默认启动页面';
    case 'List mode': return '列表模式';
    case 'Choose detail, thumbnail or extended gallery cards': return '选择详情、缩略图或扩展画廊卡片样式';
    case 'Detail size': return '详情大小';
    case 'Gallery card size in detail and extended modes': return '详情和扩展模式中的画廊卡片大小';
    case 'Thumb size': return '缩略图大小';
    case 'Thumbnail column size in thumbnail mode': return '缩略图模式中的缩略图列宽';
    case 'History size': return '历史记录数量';
    case 'Maximum stored gallery history records': return '最多保存的画廊历史记录数量';
    case 'Show Japanese title': return '显示日文标题';
    case 'Prefer original title when available': return '可用时优先显示原始标题';
    case 'Show gallery pages': return '显示画廊页数';
    case 'Display page count in gallery list rows': return '在画廊列表中显示页数';
    case 'Show gallery rating': return '显示画廊评分';
    case 'Display rating in thumbnail cards': return '在缩略图卡片中显示画廊评分';
    case 'Show gallery language': return '显示画廊语言';
    case 'Display language in thumbnail cards': return '在缩略图卡片中显示画廊语言';
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
    case 'Choose how reader pages fit the screen': return '选择阅读页面适应屏幕的方式';
    case 'Adaptive dual page': return '自适应一屏双页';
    case 'Show two wide or narrow pages together when both fit on screen': return '当两张横向或纵向页面能够容纳时在一屏内同时显示';
    case 'Start position': return '开页位置';
    case 'Where a gallery starts when opened': return '页面打开时的初始对齐位置';
    case 'Auto transfer time': return '自动翻页时间';
    case 'Delay before automatically advancing to the next page': return '自动翻到下一页前的等待时间';
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
    case 'Follow the system proxy by default; Off bypasses it; HTTP uses a custom proxy':
      return '默认遵循系统代理；关闭时跳过系统代理；HTTP 使用自定义代理';
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
    case 'Encrypt DNS queries and reduce DNS pollution': return '加密 DNS 查询并减少 DNS 污染';
    case 'Select a certificate-validated RFC 8484 resolver': return '选择启用证书校验的 RFC 8484 解析服务';
    case 'Bypass SNI blocking using built-in host fronting': return '使用内置 hosts 绕过 SNI 封锁';
    case 'Use direct connection when the selected site responds within 5s': return '所选站点 5 秒内可直连时不使用 hosts 和域名前置';
    case 'Export data': return '导出数据';
    case 'Save settings, history, downloads and filter rules to a JSON file': return '将设置、历史记录、下载和过滤规则保存为 JSON 文件';
    case 'Import data': return '导入数据';
    case 'Restore settings and local data from a supported backup file': return '从支持的备份文件恢复设置和本地数据';
    case 'Wi-Fi server/client': return 'Wi-Fi 服务器/客户端';
    case 'Wi-Fi Direct transfer': return 'Wi-Fi 直连传输';
    case 'Transfer bookmarks, local favorites, downloads and image files directly between nearby devices':
      return '在附近设备间直连传输搜索书签、本地收藏、下载记录和图片文件';
    case 'Send data': return '发送数据';
    case 'Create a Wi-Fi Direct group': return '创建 Wi-Fi 直连群组';
    case 'Act as the migration server': return '作为迁移发送端';
    case 'Receive data': return '接收数据';
    case 'Discover the sending device': return '发现并连接发送设备';
    case 'Connect to the sending device': return '连接到发送设备';
    case 'Connection status': return '连接状态';
    case 'Page': return '分页';
    case 'Items': return '项目';
    case 'Local address': return '本机地址';
    case 'Gateway': return '默认网关';
    case 'Port': return '端口';
    case 'Connected device': return '已连接设备';
    case 'Data to send': return '要发送的数据';
    case 'Search bookmarks': return '搜索书签';
    case 'Saved quick searches and their search options': return '已保存的快捷搜索及搜索条件';
    case 'Local favorites': return '本地收藏';
    case 'Locally saved gallery information': return '保存在本机的画廊信息';
    case 'Download records': return '下载记录';
    case 'Downloads and images': return '下载记录和图片';
    case 'Transfer download records and all downloaded image files': return '传输下载记录及全部已下载图片文件';
    case 'Download labels and gallery records; image files are not transferred': return '下载标签和画廊记录；不传输图片文件';
    case 'Server address': return '服务器地址';
    case 'The default gateway is filled automatically. You can also enter the sender IPv4 address.':
      return '会自动填入默认网关，也可以手动输入发送端的 IPv4 地址。';
    case 'Start sending': return '开始发送';
    case 'Stop sending': return '停止发送';
    case 'Connect and receive': return '连接并接收';
    case 'Disconnect': return '断开连接';
    case 'Stop Wi-Fi Direct': return '停止 Wi-Fi 直连';
    case 'Scan nearby devices': return '扫描附近设备';
    case 'Nearby devices': return '附近设备';
    case 'Nearby device': return '附近设备';
    case 'Connect': return '连接';
    case 'Start scanning, then select the sender device from the list': return '开始扫描，然后从列表中选择发送设备';
    case 'Progress': return '进度';
    case 'Image files': return '图片文件';
    case 'This device': return '本机设备';
    case 'Wi-Fi Direct instructions': return 'Wi-Fi 直连说明';
    case 'On the sending device, choose the data and start sending. On the receiving device, scan and select the sender.':
      return '在发送设备选择数据并开始发送；在接收设备扫描并选择发送设备。';
    case 'Keep both transfer pages open until completion. Download transfer includes metadata and downloaded image files.':
      return '传输完成前请保持两端页面开启；下载传输包含元数据和已下载图片文件。';
    case 'The direct group and data server stop automatically when this page is closed.':
      return '关闭此页面后，直连群组和数据服务器会自动停止。';
    case 'Compatible with the original Android app': return '兼容原 Android 应用';
    case 'Both devices must be on the same local network. The original Android client only connects to the gateway, so use the sending device hotspot when transferring to it.':
      return '两台设备必须处于同一局域网。原 Android 客户端只连接默认网关，因此向其传输时请开启发送设备的热点。';
    case 'Keep both transfer pages open until every page is confirmed. Wi-Fi transfer sends metadata only and does not copy downloaded images.':
      return '所有分页确认完成前请保持两端传输页面开启。Wi-Fi 迁移只传输元数据，不复制已下载图片。';
    case 'Only start the server on a trusted local network. It stops automatically when this page is closed.':
      return '请只在可信局域网中启动服务器；关闭此页面后服务器会自动停止。';
    case 'Wi-Fi transfer is idle': return 'Wi-Fi 传输空闲';
    case 'Wi-Fi transfer needs app context': return 'Wi-Fi 传输需要应用上下文';
    case 'Wi-Fi transfer stopped': return 'Wi-Fi 传输已停止';
    case 'No data is available for this transfer': return '没有可传输的数据';
    case 'Turn on Wi-Fi before using Wi-Fi Direct': return '使用 Wi-Fi 直连前请先打开 WLAN';
    case 'Preparing transfer data': return '正在准备传输数据';
    case 'Waiting for a receiving device with Wi-Fi Direct': return '正在等待接收设备通过 Wi-Fi 直连加入';
    case 'Searching for nearby devices': return '正在搜索附近设备';
    case 'Select the sending device': return '请选择发送设备';
    case 'The selected device is no longer available': return '所选设备已不可用';
    case 'Connecting with Wi-Fi Direct': return '正在通过 Wi-Fi 直连连接';
    case 'Wi-Fi Direct connection was disconnected': return 'Wi-Fi 直连已断开';
    case 'Wi-Fi Direct connected; waiting for data channel': return 'Wi-Fi 直连成功，正在等待数据通道';
    case 'Starting Wi-Fi server': return '正在启动 Wi-Fi 服务器';
    case 'Waiting for a receiving device': return '正在等待接收设备';
    case 'Receiving device connected; sending data': return '接收设备已连接，正在发送数据';
    case 'Receiving device disconnected; waiting again': return '接收设备已断开，重新等待连接';
    case 'Connecting to sending device': return '正在连接发送设备';
    case 'Connected and ready to receive': return '已连接，等待接收数据';
    case 'The sending device disconnected': return '发送设备已断开连接';
    case 'Enter a valid IPv4 server address': return '请输入有效的服务器 IPv4 地址';
    case 'Sending data': return '正在发送数据';
    case 'Receiving data': return '正在接收数据';
    case 'Sending data and downloaded images': return '正在发送数据和已下载图片';
    case 'Sending downloaded images': return '正在发送已下载图片';
    case 'Receiving downloaded images': return '正在接收已下载图片';
    case 'Transfer completed': return '传输完成';
    case 'Received and saved transfer data': return '已接收并保存传输数据';
    case 'Waiting for page confirmation': return '等待接收端确认当前分页';
    case 'The receiving device did not confirm the data in time': return '接收设备未在规定时间内确认数据';
    case 'Received data is not compatible': return '接收的数据格式不兼容';
    case 'Declaration': return '声明';
    case 'Current HarmonyOS repository': return '当前 HarmonyOS 仓库';
    case 'Author': return '作者';
    case 'xiaojieonly/Ehviewer_CN_SXJ contributors': return 'xiaojieonly/Ehviewer_CN_SXJ 贡献者';
    case 'Open the latest project release': return '打开项目的最新发布版本';
    case 'Issue help': return '问题帮助';
    case 'Open the project issue tracker': return '打开项目问题反馈页面';
    case 'License': return '许可证';
    case 'Open-source license used by this project': return '本项目使用的开源许可';
    case 'Version': return '版本';
    case 'Git commit': return 'Git 提交';
    case 'Branch and describe from the build workspace': return '构建工作区分支和 describe 信息';
    case 'Check for updates': return '检查更新';
    case 'Check the latest GitHub release': return '检查 GitHub 最新发布版本';
    case 'Update tag translation database': return '更新标签翻译数据库';
    case 'Check for and download the latest Chinese tag translations': return '检查并下载最新的中文标签翻译数据';
    case 'Checking tag translation database...': return '正在检查标签翻译数据库...';
    case 'Downloading tag translation database...': return '正在下载标签翻译数据库...';
    case 'Tag translation database is up to date': return '标签翻译数据库已是最新版本';
    case 'Tag translation database update needs an ability context': return '更新标签翻译数据库需要 Ability 上下文';
    case 'invalid database version': return '数据库版本无效';
    case 'invalid database JSON': return '数据库 JSON 无效';
    case 'database version mismatch': return '数据库版本校验不一致';
    case 'database has no tag data': return '数据库中没有标签数据';
    case 'database contains too few tags': return '数据库标签数量异常';
    case 'network request failed': return '网络请求失败';
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
    case 'Support project development': return '支持项目开发';
    case 'Choose the app interface theme': return '选择应用界面主题';
    case 'Theme color': return '主题色';
    case 'Choose the accent color used by app bars, buttons and selected items': return '选择标题栏、按钮和选中项使用的强调色';
    case 'Blue': return '蓝色';
    case 'Sky Blue': return '天蓝色';
    case 'Teal': return '青绿色';
    case 'Green': return '绿色';
    case 'Purple': return '紫色';
    case 'Orange': return '橙色';
    case 'Rose': return '玫红色';
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
    case 'Donation is not available in this version.': return '当前版本暂不支持捐赠。';
    case 'This setting is not available yet.': return '此设置暂不可用。';
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
  const options: string[] = ['All'].concat(DOWNLOAD_STATUS_FILTER_OPTIONS);
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
  if (panel === SettingsPanel.TranslationPrompt) {
    return 'System prompts';
  }
  return 'Settings';
}

export function settingsRowsForPanel(panel: SettingsPanel, themeName: string, entries: SettingEntry[]): SettingsRowItem[] {
  if (panel === SettingsPanel.Eh) {
    const followSystemDarkMode = settingEntryValue(entries, 'follow_system_dark_mode', 'Off') === 'On';
    const listMode = settingEntryValue(entries, 'list_mode', 'Detail');
    const rows: SettingsRowItem[] = [
      staticSettingsRow('identity_cookie', 'Identity cookies', 'View or import ipb_member_id, ipb_pass_hash and igneous', '', 'navigation'),
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
      staticSettingsRow('filter', 'Filter', 'Keyword/gallery filtering rules', '', 'navigation'),
      optionSettingsRow('show_eh_limits', 'Show EH limits', 'Display account and image limits in the drawer', entries, ON_OFF_OPTIONS),
      optionSettingsRow('cellular_network_warning', 'Cellular network warning', 'Warn before network-heavy operations on mobile data', entries, ON_OFF_OPTIONS)
    );
    return rows;
  }

  if (panel === SettingsPanel.Read) {
    const readingDirection = normalizeReadingDirectionOption(settingEntryValue(entries, 'reading_direction', 'Right to left'));
    const continuousMode = readingDirection === 'Top to bottom';
    const adaptiveDualPage = settingEntryValue(entries, 'adaptive_dual_page', 'Off') === 'On';
    return [
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
      optionSettingsRow('start_position', 'Start position', 'Where a gallery starts when opened', entries, ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center']),
      optionSettingsRow('start_transfer_time', 'Auto transfer time', 'Delay before automatically advancing to the next page', entries, readerAutoTransferTimeOptions()),
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
    rows.push(staticSettingsRow('export_data', 'Export data', 'Save settings, history, downloads and filter rules to a JSON file', 'Export', 'action'));
    rows.push(staticSettingsRow('import_data', 'Import data', 'Restore settings and local data from a supported backup file', 'Import', 'action'));
    rows.push(staticSettingsRow('wifi_transfer', 'Wi-Fi Direct transfer',
      'Transfer bookmarks, local favorites, downloads and image files directly between nearby devices', '',
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

export function topListChipColor(index: number): string {
  const colors: string[] = ['#2F6F8F', '#7A5A22', '#327A5B', '#A04462', '#4D6D8C', '#805A8F', '#8A4F2B', '#556B2F', '#6B7280', '#1F6B63'];
  return colors[index % colors.length];
}
