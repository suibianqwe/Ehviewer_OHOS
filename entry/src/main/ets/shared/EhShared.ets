import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { i18n } from '@kit.LocalizationKit';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { DownloadDirectoryScanResult, RestoredDownloadGallery, ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore, SettingEntry, defaultSettingEntries } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryListLoadResult, GalleryPageLoadResult, NetworkDiagnosticResult, RateGalleryResult, SignInResult, ToggleFavoriteResult, TopListLoadResult } from '../services/EhHttpClient';
import { EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, readerImageCache } from '../services/ReaderImageCache';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { MigrationTask, migrationTasks } from '../services/MigrationStatus';
import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, ehFilterStore } from '../services/EhFilterStore';

export interface EhBackupBundle {
  version: number;
  exportedAt: string;
  cookies: string;
  settings: SettingEntry[];
  history: GalleryInfo[];
  downloadItems: DownloadInfo[];
  downloadLabels: DownloadLabel[];
  filterRules: FilterRule[];
}

export const LANGUAGE_REVISION_KEY: string = 'ehviewer_language_revision';

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
  Migration = 'migration',
  WebView = 'webview',
  Filter = 'filter'
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
  { panel: SettingsPanel.Privacy, title: 'Privacy', icon: 'P', summary: 'Lock, clipboard and local data controls' },
  { panel: SettingsPanel.Advanced, title: 'Advanced', icon: 'A', summary: 'Network, cache, hosts and diagnostics' },
  { panel: SettingsPanel.About, title: 'About', icon: 'I', summary: 'Version, license and migration status' }
];

export function notifyLanguageChanged(): void {
  const current = AppStorage.get<number>(LANGUAGE_REVISION_KEY);
  AppStorage.setOrCreate<number>(LANGUAGE_REVISION_KEY, current === undefined ? 1 : current + 1);
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

export function uiStatusText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  if (text === 'Loading galleries...') {
    return '正在加载画廊...';
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
  if (text === 'Running network diagnostics...') {
    return '正在运行网络诊断...';
  }
  if (text === 'No other page to jump to') {
    return '没有可跳转的其他页面';
  }
  if (text === 'Random needs a loaded gallery list') {
    return '随机功能需要先加载画廊列表';
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
  if (text.indexOf('Saved network setting: ') === 0) {
    return '已保存网络设置：' + text.substring('Saved network setting: '.length);
  }
  if (text.indexOf('Saved: ') === 0) {
    return '已保存：' + text.substring('Saved: '.length);
  }
  if (text.indexOf('Network diagnostics: ') === 0) {
    return '网络诊断：' + text.substring('Network diagnostics: '.length);
  }
  return uiText(text);
}

export function uiPageText(prefix: string, page: number): string {
  return shouldUseChineseUi() ? prefix + page.toString() + ' 页' : prefix + page.toString();
}

export function zhText(text: string): string {
  switch (text) {
    case 'Homepage': return '主页';
    case 'Subscription': return '订阅';
    case 'What\'s Hot': return '热门';
    case 'Top Lists': return '排行';
    case 'Favourite': return '收藏';
    case 'Favorites': return '收藏';
    case 'History': return '历史';
    case 'Downloads': return '下载';
    case 'Download': return '下载';
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
    case 'Actions': return '操作';
    case 'Close': return '关闭';
    case 'Filter': return '过滤';
    case 'Filter On': return '过滤已开';
    case 'Filter mode': return '过滤模式';
    case 'Jump': return '跳转';
    case 'Random': return '随机';
    case 'Search': return '搜索';
    case 'Search galleries': return '搜索画廊';
    case 'Search downloads': return '搜索下载';
    case 'Information': return '信息';
    case 'Tags': return '标签';
    case 'No tags parsed': return '暂无标签';
    case 'Previews': return '预览';
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
    case 'Archive': return '归档';
    case 'Archive -': return '归档 -';
    case 'Share': return '分享';
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
    case 'Fit width': return '适应宽度';
    case 'Fit height': return '适应高度';
    case 'Smart fit': return '智能适配';
    case 'Image page failed to load': return '图片页面加载失败';
    case 'Image page is loading': return '图片页面加载中';
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
    case 'Migration': return '迁移状态';
    case 'Migration status': return '迁移状态';
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
    case 'Left to right': return '从左到右';
    case 'Right to left': return '从右到左';
    case 'Vertical': return '纵向';
    case 'Beginning': return '开头';
    case 'Last read': return '上次阅读';
    case 'End': return '末尾';
    case 'Not set': return '未设置';
    case 'App files': return '应用文件';
    case 'Small': return '小';
    case 'Large': return '大';
    case 'XLarge': return '超大';
    case 'Compact': return '紧凑';
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
    case 'Domain fronting': return '域名前置';
    case 'Account, site, gallery list and comments': return '账号、站点、画廊列表和评论';
    case 'Reader direction, scaling and screen behavior': return '阅读方向、缩放和屏幕行为';
    case 'Location, threads, preload and cleanup': return '位置、线程、预加载和清理';
    case 'Lock, clipboard and local data controls': return '锁定、剪贴板和本地数据控制';
    case 'Network, cache, hosts and diagnostics': return '网络、缓存、hosts 和诊断';
    case 'Version, license and migration status': return '版本、许可和迁移状态';
    case 'Settings follow the original Android header groups': return '设置按原 Android 应用分组';
    case 'Account session': return '账号会话';
    case 'Cookie session is available. Open to replace or inspect cookies.': return 'Cookie 会话可用。打开后可替换或查看 Cookie。';
    case 'Open password, WebView or Cookie sign-in. This matches the original startup sign-in flow.': return '打开密码、网页或 Cookie 登录，保持原应用启动登录流程。';
    case 'Clear the persisted identity cookies': return '清除已保存的身份 Cookie';
    case 'Original app cycles Light, Dark and Black from drawer/footer and Settings': return '原应用可在抽屉/底部和设置中切换亮色、暗色、黑色主题';
    case 'Open the HarmonyOS port checklist': return '打开 HarmonyOS 移植清单';
    case 'Identity cookies': return '身份 Cookie';
    case 'View or import ipb_member_id, ipb_pass_hash and igneous': return '查看或导入 ipb_member_id、ipb_pass_hash 和 igneous';
    case 'Gallery site': return '画廊站点';
    case 'Original setting chooses E-Hentai or ExHentai where supported': return '按原设置选择 E-Hentai 或可用时的 ExHentai';
    case 'Account configuration page, requires sign in': return '账号配置页面，需要登录';
    case 'User tag set management, requires sign in': return '用户标签集管理，需要登录';
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
    case 'Keyword/gallery filtering rules': return '关键字/画廊过滤规则';
    case 'Blacklist': return '黑名单';
    case 'Hide matching galleries': return '隐藏匹配的画廊';
    case 'Show EH limits': return '显示 EH 限制';
    case 'Display account and image limits in the drawer': return '在抽屉中显示账号和图片限制';
    case 'Cellular network warning': return '移动网络警告';
    case 'Warn before network-heavy operations on mobile data': return '使用移动数据进行大量网络操作前提示';
    case 'Screen rotation': return '屏幕旋转';
    case 'Reader orientation policy': return '阅读器方向策略';
    case 'Reading direction': return '阅读方向';
    case 'Left-to-right, right-to-left or vertical reader movement': return '从左到右、从右到左或纵向阅读';
    case 'Page scaling': return '页面缩放';
    case 'Fit width, fit height or original page scaling': return '适应宽度、适应高度或原始大小';
    case 'Start position': return '起始位置';
    case 'Where a gallery starts when opened': return '打开画廊时的起始页';
    case 'Auto transfer time': return '自动翻页时间';
    case 'Automatic next-page delay from original seekbar preference': return '原应用滑动条设置的自动下一页延迟';
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
    case 'Screen lightness': return '屏幕亮度';
    case 'Custom reader brightness when enabled': return '启用后使用自定义阅读亮度';
    case 'Download location': return '下载位置';
    case 'HarmonyOS file picker/storage mapping for downloaded galleries': return '下载画廊的 HarmonyOS 文件选择器/存储映射';
    case 'Media scan': return '媒体扫描';
    case 'Expose downloaded images to system media index': return '将下载图片暴露给系统媒体索引';
    case 'Multi-thread download': return '多线程下载';
    case 'Worker count used by the original SpiderQueen pipeline': return '原 SpiderQueen 下载管线使用的工作线程数';
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
    case 'Scan downloaded folders not present in queue': return '扫描不在队列中的下载文件夹';
    case 'Pattern protection': return '图案保护';
    case 'Original SetSecurityActivity equivalent': return '原 SetSecurityActivity 对应功能';
    case 'Secure screen': return '安全屏幕';
    case 'Prevent screenshots and insecure previews': return '禁止截图和不安全预览';
    case 'Analytics': return '数据统计';
    case 'Allow privacy-preserving analytics prompt equivalent': return '允许隐私提示对应的数据统计设置';
    case 'About analytics': return '关于数据统计';
    case 'Explanation dialog from the original privacy settings': return '原隐私设置中的说明对话框';
    case 'Save parse error body': return '保存解析错误正文';
    case 'Persist parser failures for debugging': return '保存解析失败内容用于调试';
    case 'Save crash log': return '保存崩溃日志';
    case 'Persist crash logs locally': return '在本地保存崩溃日志';
    case 'Dump logcat': return '导出 logcat';
    case 'Android logcat equivalent needs Harmony logging export': return 'Android logcat 等价功能需要 Harmony 日志导出';
    case 'Clear download path cache': return '清除下载路径缓存';
    case 'Refresh cached file path and size lookups': return '刷新缓存的文件路径和大小查询';
    case 'Clear memory cache': return '清除内存缓存';
    case 'Drop reader image and page caches': return '清除阅读器图片和页面缓存';
    case 'Reader cache budget': return '阅读器缓存容量';
    case 'Language override': return '语言覆盖设置';
    case 'System proxy or direct connection': return '系统代理或直连';
    case 'Test E, EX, forums and repo connectivity with current settings': return '按当前设置测试 E、EX、论坛和仓库连通性';
    case 'Force bundled host overrides; leave Off for normal Cloudflare DNS': return '强制使用内置 host；正常 Cloudflare DNS 请保持关闭';
    case 'Force bundled ExHentai host overrides; leave Off unless your network needs them': return '强制使用内置 ExHentai host；仅在网络需要时开启';
    case 'Use DoH resolver': return '使用 DoH 解析器';
    case 'Original network compatibility switch': return '原应用网络兼容性开关';
    case 'Export data': return '导出数据';
    case 'Export settings, database and app state': return '导出设置、数据库和应用状态';
    case 'Import data': return '导入数据';
    case 'Import backup data': return '导入备份数据';
    case 'Wi-Fi server/client': return 'Wi-Fi 服务器/客户端';
    case 'Original Wi-Fi transfer tools': return '原应用 Wi-Fi 传输工具';
    case 'Declaration': return '声明';
    case 'Original declaration and project notice': return '原应用声明和项目说明';
    case 'Author': return '作者';
    case 'xiaojieonly/Ehviewer_CN_SXJ contributors': return 'xiaojieonly/Ehviewer_CN_SXJ 贡献者';
    case 'Latest release': return '最新版本';
    case 'GitHub releases URL from original settings': return '原设置中的 GitHub releases 地址';
    case 'Issue help': return '问题帮助';
    case 'Issue guide URL from original settings': return '原设置中的问题反馈地址';
    case 'License': return '许可证';
    case 'Open-source license view': return '开源许可证查看';
    case 'Version': return '版本';
    case 'HarmonyOS port workspace version': return 'HarmonyOS 移植工作区版本';
    case 'Check for updates': return '检查更新';
    case 'Original AppUpdater entry': return '原 AppUpdater 入口';
    case 'Close automatic updates': return '关闭自动更新';
    case 'Disable startup update check': return '禁用启动时更新检查';
    case 'Donate': return '捐赠';
    case 'Original donation entry': return '原应用捐赠入口';
    case 'Download items will be shown here': return '下载项会显示在这里';
    case 'No items match the current filter': return '没有符合当前过滤条件的项目';
    case 'Waiting for toplist.php': return '等待 toplist.php';
    case 'Signing in...': return '正在登录...';
    default: return text;
  }
}

let activeBackHandler: (() => boolean) | null = null;

export function setActiveBackHandler(handler: (() => boolean) | null): void {
  activeBackHandler = handler;
}

export function runActiveBackHandler(): boolean {
  return activeBackHandler !== null && activeBackHandler();
}
export const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';

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

export function cloneStringArray(values: string[] | undefined): string[] | undefined {
  if (values === undefined) {
    return undefined;
  }
  const result: string[] = [];
  for (let i = 0; i < values.length; i++) {
    result.push(values[i]);
  }
  return result;
}

export function cloneRequiredStringArray(values: string[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < values.length; i++) {
    result.push(values[i]);
  }
  return result;
}

export function cloneGalleryInfo(gallery: GalleryInfo): GalleryInfo {
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
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: cloneStringArray(gallery.simpleTags),
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: gallery.favoriteSlot,
    favoriteName: gallery.favoriteName,
    tagList: cloneStringArray(gallery.tagList)
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

export function cloneGalleryTagGroups(groups: GalleryTagGroup[]): GalleryTagGroup[] {
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: cloneRequiredStringArray(groups[i].tags)
    });
  }
  return result;
}

export function cloneGalleryComments(comments: GalleryComment[]): GalleryComment[] {
  const result: GalleryComment[] = [];
  for (let i = 0; i < comments.length; i++) {
    result.push({
      id: comments[i].id,
      user: comments[i].user,
      posted: comments[i].posted,
      content: comments[i].content,
      score: comments[i].score
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

export function cloneTopListItem(item: TopListItem): TopListItem {
  return {
    href: item.href,
    gid: item.gid,
    token: item.token,
    tag: item.tag,
    value: item.value
  };
}

export function cloneTopListBucket(bucket: TopListBucket): TopListBucket {
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

export function cloneTopListInfo(info: TopListInfo): TopListInfo {
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
  const maxSize = parseHistoryMaxSize(ehSettingsStore.getValue('history_info_size', '100'));
  ehHistoryStore.addGallery(gallery, maxSize);
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehHistoryStore.save(context).catch(() => {});
}

export function saveGalleryReadPosition(gid: number, pageIndex: number): void {
  ehHistoryStore.setReadPage(gid, pageIndex);
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehHistoryStore.save(context).catch(() => {});
}

export function readerStartIndex(detail: GalleryDetail): number {
  if (detail.previewSet.length === 0) {
    return 0;
  }
  const startPosition = ehSettingsStore.getValue('start_position', 'Beginning');
  if (startPosition === 'End') {
    return detail.previewSet.length - 1;
  }
  if (startPosition === 'Last read') {
    const saved = ehHistoryStore.getReadPage(detail.gid);
    if (saved >= 0 && saved < detail.previewSet.length) {
      return saved;
    }
  }
  return 0;
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

  ehDownloadStore.addGallery(gallery, '');
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
  sortMode: string): DownloadInfo[] {
  const normalizedQuery = query.toLowerCase().trim();
  const filtered: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (statusFilter !== 'All' && downloadStateLabel(item.state) !== statusFilter) {
      continue;
    }
    if (labelFilter !== 'All' && downloadLabelName(item.label) !== labelFilter) {
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

export function downloadItemMatches(item: DownloadInfo, query: string): boolean {
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
    if (sortMode === 'Name asc') {
      return left.title.localeCompare(right.title);
    }
    if (sortMode === 'Name desc') {
      return right.title.localeCompare(left.title);
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
  const options: string[] = ['Default', 'GID asc', 'GID desc', 'Rating desc', 'Name asc', 'Name desc'];
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

export function nextDownloadState(current: DownloadState): DownloadState {
  if (current === DownloadState.None) {
    return DownloadState.Wait;
  }
  if (current === DownloadState.Wait) {
    return DownloadState.Downloading;
  }
  if (current === DownloadState.Downloading) {
    return DownloadState.Finish;
  }
  if (current === DownloadState.Finish) {
    return DownloadState.Failed;
  }
  return DownloadState.None;
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

export function downloadLabelName(label: string): string {
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
    return '#5A8FA8';
  }
  if (state === DownloadState.Downloading) {
    return '#2F6F8F';
  }
  if (state === DownloadState.Finish) {
    return '#0A6B45';
  }
  if (state === DownloadState.Failed || state === DownloadState.Invalid) {
    return '#B42318';
  }
  return '#667085';
}

export const APP_THEME_COLOR: string = '#2F6F8F';

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

export function mixHexColor(from: string, to: string, amount: number): string {
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

export function nextFloatingToolbarVisible(scrollOffset: number, contentOffset: number, currentVisible: boolean): boolean {
  if (contentOffset <= 4) {
    return true;
  }
  if (scrollOffset > 6) {
    return false;
  }
  if (scrollOffset < -6) {
    return true;
  }
  return currentVisible;
}

export function nextFloatingToolbarOffset(currentOffset: number, scrollOffset: number, contentOffset: number,
  barHeight: number): number {
  if (contentOffset <= 4) {
    return 0;
  }
  const nextOffset = currentOffset - scrollOffset;
  return Math.max(-barHeight, Math.min(0, nextOffset));
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
  return 'W ' + wait.toString() + ' / D ' + active.toString() + ' / OK ' + done.toString() + ' / F ' + failed.toString();
}

export function parseHistoryMaxSize(value: string): number {
  const parsed = Number.parseInt(value);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return 100;
  }
  return parsed;
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
  if (panel === SettingsPanel.Migration) {
    return 'Migration';
  }
  return 'Settings';
}

export function settingsRowsForPanel(panel: SettingsPanel, themeName: string, entries: SettingEntry[]): SettingsRowItem[] {
  if (panel === SettingsPanel.Eh) {
    return [
      staticSettingsRow('identity_cookie', 'Identity cookies', 'View or import ipb_member_id, ipb_pass_hash and igneous', 'Session', 'action'),
      optionSettingsRow('gallery_site', 'Gallery site', 'Original setting chooses E-Hentai or ExHentai where supported', entries, ['E-Hentai', 'ExHentai']),
      staticSettingsRow('u_config', 'UConfig', 'Account configuration page, requires sign in', 'Open', 'action'),
      staticSettingsRow('my_tags', 'My Tags', 'User tag set management, requires sign in', 'Open', 'action'),
      optionSettingsRow('launch_page', 'Launch page', 'Default start scene after warnings and sign-in checks', entries, ['Homepage', 'Subscription', 'What\'s Hot', 'Favorites']),
      optionSettingsRow('list_mode', 'List mode', 'Gallery list style from original Android preferences', entries, ['Detail', 'Thumb', 'Extended']),
      optionSettingsRow('detail_size', 'Detail size', 'Gallery detail image and metadata density', entries, ['Default', 'Compact', 'Large']),
      optionSettingsRow('thumb_size', 'Thumb size', 'Thumbnail size used in gallery rows', entries, ['Small', 'Large', 'XLarge']),
      optionSettingsRow('history_info_size', 'History size', 'Maximum stored gallery history records', entries, ['50', '100', '200', '500']),
      optionSettingsRow('show_jpn_title', 'Show Japanese title', 'Prefer original title when available', entries, ON_OFF_OPTIONS),
      optionSettingsRow('show_gallery_pages', 'Show gallery pages', 'Display page count in gallery list rows', entries, ON_OFF_OPTIONS),
      optionSettingsRow('show_tag_translations', 'Show tag translations', 'Use translated tag labels when data is available', entries, ON_OFF_OPTIONS),
      staticSettingsRow('filter', 'Filter', 'Keyword/gallery filtering rules', 'Open', 'action'),
      staticSettingsRow('blacklist', 'Blacklist', 'Hide matching galleries from lists (uses same filter rules)', 'Open', 'action'),
      optionSettingsRow('show_eh_limits', 'Show EH limits', 'Display account and image limits in the drawer', entries, ON_OFF_OPTIONS),
      optionSettingsRow('cellular_network_warning', 'Cellular network warning', 'Warn before network-heavy operations on mobile data', entries, ON_OFF_OPTIONS)
    ];
  }

  if (panel === SettingsPanel.Read) {
    return [
      optionSettingsRow('screen_rotation', 'Screen rotation', 'Reader orientation policy', entries, ['System', 'Portrait', 'Landscape']),
      optionSettingsRow('reading_direction', 'Reading direction', 'Left-to-right, right-to-left or vertical reader movement', entries, ['Left to right', 'Right to left', 'Vertical']),
      optionSettingsRow('page_scaling', 'Page scaling', 'Fit width, fit height or original page scaling', entries, ['Fit width', 'Fit height', 'Original', 'Smart fit']),
      optionSettingsRow('start_position', 'Start position', 'Where a gallery starts when opened', entries, ['Beginning', 'Last read', 'End']),
      optionSettingsRow('start_transfer_time', 'Auto transfer time', 'Automatic next-page delay from original seekbar preference', entries, ['Off', '2s', '5s', '10s', '15s']),
      optionSettingsRow('keep_screen_on', 'Keep screen on', 'Prevent screen sleep while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_clock', 'Show clock', 'Show clock overlay in the reader', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_progress', 'Show progress', 'Show reader progress overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('gallery_show_battery', 'Show battery', 'Show battery overlay', entries, ON_OFF_OPTIONS),
      optionSettingsRow('volume_page', 'Volume page', 'Use volume buttons to turn pages', entries, ON_OFF_OPTIONS),
      optionSettingsRow('reading_fullscreen', 'Reading fullscreen', 'Hide system chrome while reading', entries, ON_OFF_OPTIONS),
      optionSettingsRow('screen_lightness', 'Screen lightness', 'Custom reader brightness when enabled', entries, ['0%', '25%', '50%', '75%', '100%'])
    ];
  }

  if (panel === SettingsPanel.Download) {
    return [
      optionSettingsRow('download_location', 'Download location', 'HarmonyOS file picker/storage mapping for downloaded galleries', entries, ['Not set', 'App files', 'Downloads']),
      optionSettingsRow('media_scan', 'Media scan', 'Expose downloaded images to system media index', entries, ON_OFF_OPTIONS),
      optionSettingsRow('download_thread', 'Multi-thread download', 'Worker count used by the original SpiderQueen pipeline', entries, ['1', '2', '3', '4', '5', '8', '10']),
      optionSettingsRow('preload_image', 'Preload image', 'Reader/download prefetch count', entries, ['0', '3', '5', '10', '20']),
      optionSettingsRow('download_list_pagination', 'Download list pagination', 'Paginate large download lists', entries, ON_OFF_OPTIONS),
      optionSettingsRow('image_size', 'Image resolution', 'Requested E-Hentai image size', entries, ['Auto', '780x', '980x', '1280x', 'Original']),
      optionSettingsRow('download_origin_image', 'Download original image', 'Prefer original files when available', entries, ON_OFF_OPTIONS),
      optionSettingsRow('download_timeout', 'Download timeout', 'Network timeout for image tasks', entries, ['Default', '15s', '30s', '60s']),
      optionSettingsRow('download_order_asc', 'Download order ascending', 'Store pages in ascending page order', entries, ON_OFF_OPTIONS),
      staticSettingsRow('restore_download_items', 'Restore download items', 'Rebuild queue from downloaded folders', 'Run', 'action'),
      staticSettingsRow('clean_redundancy', 'Clean redundancy', 'Scan downloaded folders not present in queue', 'Scan', 'action')
    ];
  }

  if (panel === SettingsPanel.Privacy) {
    return [
      staticSettingsRow('pattern_protection', 'Pattern protection', 'Toggle biometric/screen-lock protection on app resume', 'Toggle', 'action'),
      optionSettingsRow('enable_secure', 'Secure screen', 'Prevent screenshots and insecure previews', entries, ON_OFF_OPTIONS),
      optionSettingsRow('enable_analytics', 'Analytics', 'Allow privacy-preserving analytics prompt equivalent', entries, ON_OFF_OPTIONS),
      staticSettingsRow('about_analytics', 'About analytics', 'Explanation dialog from the original privacy settings', 'Info', 'message')
    ];
  }

  if (panel === SettingsPanel.Advanced) {
    const rows: SettingsRowItem[] = [
      optionSettingsRow('save_parse_error_body', 'Save parse error body', 'Persist parser failures for debugging', entries, ON_OFF_OPTIONS),
      optionSettingsRow('save_crash_log', 'Save crash log', 'Persist crash logs locally', entries, ON_OFF_OPTIONS),
      staticSettingsRow('dump_logcat', 'Dump logcat', 'Android logcat equivalent needs Harmony logging export', 'Info', 'action'),
      staticSettingsRow('clear_download_path_cache', 'Clear download path cache', 'Refresh cached file path and size lookups', 'Run', 'action'),
      staticSettingsRow('clear_memory_cache', 'Clear memory cache', 'Drop reader image and page caches', 'Run', 'action'),
      optionSettingsRow('read_cache_size', 'Read cache size', 'Reader cache budget', entries, ['40 MB', '80 MB', '160 MB', '320 MB', '640 MB']),
      optionSettingsRow('app_language', 'App language', 'Language override', entries, ['System', 'English', 'zh-CN']),
      optionSettingsRow('proxy', 'Proxy', 'System proxy or direct connection', entries, ['System', 'Off', 'HTTP', 'SOCKS']),
      staticSettingsRow('network_diagnostics', 'Network diagnostics', 'Test E, EX, forums and repo connectivity with current settings', 'Run', 'action'),
    ];
    const proxyType = settingEntryValue(entries, 'proxy', 'System');
    if (proxyType === 'HTTP' || proxyType === 'SOCKS') {
      rows.push(textSettingsRow('proxy_host', 'Proxy host', 'Host or IP address for custom proxy', entries, '127.0.0.1'));
      rows.push(textSettingsRow('proxy_port', 'Proxy port', '1-65535', entries, '8080'));
    }
    rows.push(optionSettingsRow('built_in_hosts', 'Built-in hosts', 'Force bundled host overrides; leave Off for normal Cloudflare DNS', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('built_ex_hosts', 'Built EX hosts', 'Force bundled ExHentai host overrides; leave Off unless your network needs them', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('dns_over_https', 'DNS over HTTPS', 'Use DoH resolver', entries, ON_OFF_OPTIONS));
    rows.push(optionSettingsRow('domain_fronting', 'Domain fronting', 'Original network compatibility switch', entries, ON_OFF_OPTIONS));
    rows.push(staticSettingsRow('export_data', 'Export data', 'Save settings, history, downloads and filter rules to a JSON file', 'Export', 'action'));
    rows.push(staticSettingsRow('import_data', 'Import data', 'Restore from a previously exported JSON backup', 'Import', 'action'));
    rows.push(staticSettingsRow('wifi_transfer', 'Wi-Fi server/client', 'Original Wi-Fi transfer tools', 'Not migrated', 'activity'));
    return rows;
  }

  if (panel === SettingsPanel.About) {
    return [
      staticSettingsRow('declaration', 'Declaration', 'Original declaration and project notice', 'Info', 'message'),
      staticSettingsRow('author', 'Author', 'xiaojieonly/Ehviewer_CN_SXJ contributors', '', 'message'),
      staticSettingsRow('latest_release', 'Latest release', 'GitHub releases URL from original settings', 'Link', 'url'),
      staticSettingsRow('issue_help', 'Issue help', 'Issue guide URL from original settings', 'Link', 'url'),
      staticSettingsRow('license', 'License', 'Open-source license view', 'GPL', 'activity'),
      staticSettingsRow('version', 'Version', 'HarmonyOS port workspace version', '0.1.26', 'version'),
      staticSettingsRow('check_for_updates', 'Check for updates', 'Original AppUpdater entry', 'Open', 'action'),
      optionSettingsRow('close_auto_updates', 'Close automatic updates', 'Disable startup update check', entries, ON_OFF_OPTIONS),
      staticSettingsRow('donate', 'Donate', 'Original donation entry', 'Not migrated', 'url')
    ];
  }

  return [staticSettingsRow('theme', 'Theme', 'Current staged theme', themeName, 'list')];
}

export const ON_OFF_OPTIONS: string[] = ['On', 'Off'];

export function optionSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], options: string[]): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: settingEntryValue(entries, key, options.length > 0 ? options[0] : ''),
    type: options.length === 2 && options[0] === 'On' && options[1] === 'Off' ? 'switch' : 'list',
    options: options
  };
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
    return 'My Tags needs the online tag management page to be migrated. Watched-tag list loading is handled by Subscription.';
  }
  if (key === 'filter') {
    return 'Filter rules need the local rule database before they can hide galleries in list scenes.';
  }
  if (key === 'blacklist') {
    return 'Blacklist storage and list filtering are not migrated yet.';
  }
  if (key === 'pattern_protection') {
    return 'Pattern protection needs a HarmonyOS lock screen flow. Secure screen preference is available.';
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

export function nextOption(current: string, options: string[]): string {
  if (options.length === 0) {
    return current;
  }
  for (let i = 0; i < options.length; i++) {
    if (options[i] === current) {
      return options[(i + 1) % options.length];
    }
  }
  return options[0];
}

export function isValidProxyPortText(value: string): boolean {
  const port = Number.parseInt(value);
  return !Number.isNaN(port) && port > 0 && port <= 65535 && port.toString() === value.trim();
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

export function defaultKeywordForRoute(route: GalleryRoute): string {
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

export function effectiveListSite(route: GalleryRoute): GallerySite {
  const site = currentGallerySite();
  if (site === GallerySite.Ex && !ehCookieStore.hasCookies() && route !== GalleryRoute.Favorites &&
    route !== GalleryRoute.Subscription) {
    return GallerySite.E;
  }
  return site;
}

export function gallerySiteName(site: GallerySite): string {
  return site === GallerySite.Ex ? 'ExHentai' : 'E-Hentai';
}

export function galleryListFailureMessage(result: GalleryListLoadResult, site: GallerySite): string {
  const status = result.statusCode > 0 ? 'HTTP ' + result.statusCode.toString() + ', ' : '';
  const url = result.url.length > 0 ? ', ' + result.url : '';
  return 'Load failed: ' + gallerySiteName(site) + ', ' + status + result.message + url;
}

export function shouldRetryGalleryListOnE(result: GalleryListLoadResult, site: GallerySite, route: GalleryRoute): boolean {
  if (site !== GallerySite.Ex || result.galleries.length > 0 || route === GalleryRoute.TopLists) {
    return false;
  }
  if (route === GalleryRoute.Subscription || route === GalleryRoute.Favorites || route === GalleryRoute.WhatsHot) {
    return true;
  }

  const message = result.message.toLowerCase();
  return message.indexOf('links 0') >= 0 || message.indexOf('blocked') >= 0 ||
    message.indexOf('login') >= 0 || message.indexOf('cookie') >= 0 ||
    message.indexOf('cloudflare') >= 0;
}

export function withGalleryListMessage(result: GalleryListLoadResult, message: string): GalleryListLoadResult {
  return {
    ok: result.ok,
    url: result.url,
    statusCode: result.statusCode,
    message: message,
    pages: result.pages,
    nextPage: result.nextPage,
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
  if (preferOriginal && page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
    return readerLocalImageSource(page.cachedOriginImagePath);
  }
  if (!preferOriginal && page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
    return readerLocalImageSource(page.cachedImagePath);
  }
  if (preferOriginal && page.originImageUrl.length > 0) {
    return page.originImageUrl;
  }
  return page.imageUrl;
}

export function cacheReaderImageForPage(page: GalleryPage, onReady: (page: GalleryPage) => void): void {
  const context = getAbilityContext();
  if (context === undefined || page.imageUrl.length === 0) {
    return;
  }

  const existing = readerImageCache.getCachedPath(context, page.imageUrl);
  if (existing.length > 0) {
    onReady(cloneGalleryPageWithCache(page, existing));
    return;
  }

  readerImageCache.ensureCached(context, page.imageUrl, page.pageUrl, true).then((path: string) => {
    if (path.length > 0) {
      onReady(cloneGalleryPageWithCache(page, path));
    }
  }).catch(() => {});
}

export function cacheThumbnailImage(url: string, onReady: (path: string) => void): void {
  const context = getAbilityContext();
  if (context === undefined || url.length === 0) {
    return;
  }

  const existing = readerImageCache.getCachedPath(context, url);
  if (existing.length > 0) {
    onReady(existing);
    return;
  }

  readerImageCache.ensureCached(context, url, EhUrl.getReferer(currentGallerySite())).then((path: string) => {
    if (path.length > 0) {
      onReady(path);
    }
  }).catch(() => {});
}

export function cloneGalleryPageWithCache(page: GalleryPage, cachedPath: string): GalleryPage {
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
  return path.startsWith('file://') ? path : 'file://' + path;
}

export function readerZoomSize(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

export function readerFullImageWidth(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

export function readerFullImageHeight(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

export function readerImageFit(fitMode: string): ImageFit {
  if (fitMode === 'Original') {
    return ImageFit.None;
  }
  if (fitMode === 'Fit height') {
    return ImageFit.Contain;
  }
  if (fitMode === 'Smart fit') {
    return ImageFit.Cover;
  }
  return ImageFit.Contain;
}

export function readerShortUrl(url: string): string {
  if (url.length <= 96) {
    return url;
  }
  return url.substring(0, 72) + '...' + url.substring(url.length - 18);
}

export function readerPreloadCount(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('preload_image', '5'));
  if (Number.isNaN(value) || value <= 0) {
    return 0;
  }
  return Math.min(value, 3);
}

export function readerIsRightToLeft(): boolean {
  return ehSettingsStore.getValue('reading_direction', 'Left to right') === 'Right to left';
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
  return gallery.title.length === 0 ? 'Untitled' : gallery.title;
}

export function showGalleryPages(): boolean {
  return ehSettingsStore.getValue('show_gallery_pages', 'Off') === 'On';
}

export function galleryListMode(): string {
  return ehSettingsStore.getValue('list_mode', 'Detail');
}

export function galleryThumbWidth(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Large');
  if (value === 'Small') {
    return 70;
  }
  if (value === 'XLarge') {
    return 104;
  }
  return 86;
}

export function galleryThumbHeight(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Large');
  if (value === 'Small') {
    return 96;
  }
  if (value === 'XLarge') {
    return 142;
  }
  return 118;
}

export function galleryRowHeight(): number {
  const height = galleryThumbHeight();
  if (galleryListMode() === 'Thumb') {
    return height;
  }
  if (galleryListMode() === 'Extended') {
    return Math.max(height, 134);
  }
  return height;
}

export function galleryTagPreview(gallery: GalleryInfo): string {
  if (gallery.simpleTags === undefined || gallery.simpleTags.length === 0) {
    return '';
  }
  const parts: string[] = [];
  const count = Math.min(gallery.simpleTags.length, 6);
  for (let i = 0; i < count; i++) {
    parts.push(gallery.simpleTags[i]);
  }
  return parts.join('  ');
}

export function detailTitleFontSize(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Default');
  if (value === 'Compact') {
    return 16;
  }
  if (value === 'Large') {
    return 20;
  }
  return 18;
}

export function detailTitleMaxLines(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Default');
  if (value === 'Compact') {
    return 3;
  }
  if (value === 'Large') {
    return 6;
  }
  return 5;
}

export function detailHeadingFontSize(): number {
  return ehSettingsStore.getValue('detail_size', 'Default') === 'Large' ? 16 : 15;
}

export function readerShowProgress(): boolean {
  return ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
}

export function readerShowClock(): boolean {
  return ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
}

export function readerClockText(): string {
  const now = new Date();
  return padTimeNumber(now.getHours()) + ':' + padTimeNumber(now.getMinutes());
}

export function padTimeNumber(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

export function topListChipColor(index: number): string {
  const colors: string[] = ['#2F6F8F', '#7A5A22', '#327A5B', '#A04462', '#4D6D8C', '#805A8F', '#8A4F2B', '#556B2F', '#6B7280', '#1F6B63'];
  return colors[index % colors.length];
}
