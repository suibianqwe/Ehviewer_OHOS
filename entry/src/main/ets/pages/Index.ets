import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
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

interface EhBackupBundle {
  version: number;
  exportedAt: string;
  cookies: string;
  settings: SettingEntry[];
  history: GalleryInfo[];
  downloadItems: DownloadInfo[];
  downloadLabels: DownloadLabel[];
  filterRules: FilterRule[];
}

interface DrawerItem {
  route: GalleryRoute;
  title: string;
  icon: string;
  subtitle: string;
}

interface SettingsHeaderItem {
  panel: SettingsPanel;
  title: string;
  icon: string;
  summary: string;
}

interface SettingsRowItem {
  key?: string;
  title: string;
  summary: string;
  value: string;
  type: string;
  options?: string[];
}

enum SessionMode {
  Password = 'password',
  Cookie = 'cookie',
  Web = 'web'
}

enum SettingsPanel {
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

const DRAWER_ITEMS: DrawerItem[] = [
  { route: GalleryRoute.Home, title: 'Homepage', icon: 'H', subtitle: 'Gallery list and search' },
  { route: GalleryRoute.Subscription, title: 'Subscription', icon: 'S', subtitle: 'Watched tags' },
  { route: GalleryRoute.WhatsHot, title: 'What\'s Hot', icon: 'F', subtitle: 'Popular galleries' },
  { route: GalleryRoute.TopLists, title: 'Top Lists', icon: 'T', subtitle: 'Ranking tables' },
  { route: GalleryRoute.Favorites, title: 'Favourite', icon: 'L', subtitle: 'Cloud and local favorites' },
  { route: GalleryRoute.History, title: 'History', icon: 'R', subtitle: 'Recent reading' },
  { route: GalleryRoute.Downloads, title: 'Downloads', icon: 'D', subtitle: 'Queue and labels' },
  { route: GalleryRoute.Settings, title: 'Settings', icon: 'G', subtitle: 'Preferences' }
];

const SETTINGS_HEADERS: SettingsHeaderItem[] = [
  { panel: SettingsPanel.Eh, title: 'EH', icon: 'E', summary: 'Account, site, gallery list and comments' },
  { panel: SettingsPanel.Read, title: 'Read', icon: 'R', summary: 'Reader direction, scaling and screen behavior' },
  { panel: SettingsPanel.Download, title: 'Download', icon: 'D', summary: 'Location, threads, preload and cleanup' },
  { panel: SettingsPanel.Privacy, title: 'Privacy', icon: 'P', summary: 'Lock, clipboard and local data controls' },
  { panel: SettingsPanel.Advanced, title: 'Advanced', icon: 'A', summary: 'Network, cache, hosts and diagnostics' },
  { panel: SettingsPanel.About, title: 'About', icon: 'I', summary: 'Version, license and migration status' }
];

function shouldUseChineseUi(): boolean {
  const language = ehSettingsStore.getValue('app_language', 'zh-CN');
  return language === 'zh-CN' || language === 'System';
}

function uiText(text: string): string {
  if (!shouldUseChineseUi()) {
    return text;
  }
  return zhText(text);
}

function uiValue(value: string): string {
  return uiText(value);
}

function uiStatusText(text: string): string {
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

function uiPageText(prefix: string, page: number): string {
  return shouldUseChineseUi() ? prefix + page.toString() + ' 页' : prefix + page.toString();
}

function zhText(text: string): string {
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
    case 'Japanese': return '日语';
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
const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';

@Entry
@Component
struct Index {
  @State activeRoute: GalleryRoute = GalleryRoute.Session;
  @State drawerOpen: boolean = false;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;

  onBackPress(): boolean {
    if (activeBackHandler !== null && activeBackHandler()) {
      return true;
    }
    if (this.drawerOpen) {
      this.closeDrawer();
      return true;
    }
    if (this.activeRoute === GalleryRoute.Settings || this.activeRoute === GalleryRoute.Downloads) {
      this.activeRoute = this.routeAfterSignIn();
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.activeRoute = GalleryRoute.Session;
      return;
    }

    ehSpiderInfoStore.load(context).catch(() => {});
    ehDownloadStore.load(context).catch(() => {});
    ehSettingsStore.load(context).then(() => {
      this.loadSessionRoute(context);
    }).catch(() => {
      this.loadSessionRoute(context);
    });
  }

  private loadSessionRoute(context: common.UIAbilityContext): void {
    ehCookieStore.load(context).then(() => {
      const signedIn = ehCookieStore.hasCookies();
      this.activeRoute = signedIn ? this.routeAfterSignIn() : GalleryRoute.Session;
      this.drawerOpen = signedIn;
    }).catch(() => {
      this.activeRoute = GalleryRoute.Session;
      this.drawerOpen = false;
    });
  }

  private routeAfterSignIn(): GalleryRoute {
    return launchRouteFromSetting(ehSettingsStore.getValue('launch_page', 'Homepage'));
  }

  private selectRoute(route: GalleryRoute): void {
    this.activeRoute = route;
  }

  private toggleDrawer(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.drawerOpen = !this.drawerOpen;
    });
  }

  private closeDrawer(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.drawerOpen = false;
    });
  }

  build() {
    Column() {
      if (!usesEmbeddedToolbar(this.activeRoute)) {
        AppToolbar({
          title: routeTitle(this.activeRoute),
          subtitle: routeSubtitle(this.activeRoute),
          onMenu: () => {
            this.toggleDrawer();
          }
        })
      }

      Row() {
        if (this.drawerOpen) {
          DrawerPanel({
            activeRoute: this.activeRoute,
            onSelect: (route: GalleryRoute) => {
              this.selectRoute(route);
            }
          })
            .transition(TransitionEffect.move(TransitionEdge.START)
              .animation({ duration: 180, curve: Curve.EaseOut }))
        }

        Column() {
          if (this.activeRoute === GalleryRoute.Home) {
            HomeGalleryScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.Subscription) {
            SubscriptionGalleryScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.WhatsHot) {
            HotGalleryScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.TopLists) {
            TopListScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.Favorites) {
            FavoriteGalleryScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.History) {
            HistoryScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.Downloads) {
            DownloadScene({
              onMenu: () => {
                this.toggleDrawer();
              }
            })
          } else if (this.activeRoute === GalleryRoute.Session) {
            SessionScene({
              onSignedIn: () => {
                this.activeRoute = this.routeAfterSignIn();
                this.drawerOpen = true;
              }
            })
          } else if (this.activeRoute === GalleryRoute.Migration) {
            MigrationScene()
          } else {
            SettingsScene({
              onMenu: () => {
                this.toggleDrawer();
              },
              onSignedIn: () => {
                this.activeRoute = this.routeAfterSignIn();
                this.drawerOpen = false;
              }
            })
              .transition(TransitionEffect.move(TransitionEdge.END)
                .animation({ duration: 300, curve: Curve.EaseOut }))
          }
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.getUIContext().px2vp(this.statusBarHeight) })
    .backgroundColor('#F3F5F7')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

@Component
struct HomeGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Homepage',
      listMode: 'Search',
      sourceRoute: GalleryRoute.Home,
      onMenu: this.onMenu
    })
  }
}

@Component
struct SubscriptionGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Subscription',
      listMode: 'Watched tags',
      sourceRoute: GalleryRoute.Subscription,
      onMenu: this.onMenu
    })
  }
}

@Component
struct HotGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'What\'s Hot',
      listMode: 'Popular',
      sourceRoute: GalleryRoute.WhatsHot,
      onMenu: this.onMenu
    })
  }
}

@Component
struct FavoriteGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Favourite',
      listMode: 'Favorites',
      sourceRoute: GalleryRoute.Favorites,
      onMenu: this.onMenu
    })
  }
}

@Component
struct AppToolbar {
  title: string = '';
  subtitle: string = '';
  onMenu: () => void = () => {};

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.open_sidebar'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(38)
      .height(38)
      .backgroundColor('rgba(255,255,255,0.15)')
      .onClick(() => {
        this.onMenu();
      })

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(uiText(this.subtitle))
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.7)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 16 })
    .backgroundColor('#2F6F8F')
  }
}

@Component
struct DrawerPanel {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  onSelect: (route: GalleryRoute) => void = () => {};
  @State signedIn: boolean = false;
  @State downloadSummary: string = 'Downloads: idle';

  aboutToAppear(): void {
    this.signedIn = ehCookieStore.hasCookies();
    this.downloadSummary = 'Downloads: ' + downloadQueueSummary(ehDownloadStore.getItems());
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadStore.load(context).then(() => {
        this.downloadSummary = 'Downloads: ' + downloadQueueSummary(ehDownloadStore.getItems());
      }).catch(() => {
        this.downloadSummary = 'Downloads: unavailable';
      });
    }
  }

  build() {
    Column() {
      DrawerHeader({ signedIn: this.signedIn })

      List({ space: 2 }) {
        ForEach(DRAWER_ITEMS, (item: DrawerItem) => {
          ListItem() {
            DrawerRow({
              item: item,
              selected: item.route === this.activeRoute,
              onTapItem: () => {
                this.onSelect(item.route);
              }
            })
          }
        }, (item: DrawerItem) => item.route + ':' + this.activeRoute)
      }
      .layoutWeight(1)
      .width('100%')

      Column() {
        Text(this.signedIn ? uiText('Session') : uiText('Guest mode'))
          .fontSize(12)
          .fontColor('#667085')
        Text(this.signedIn ? uiText('Cookie session active') : uiText('Open Settings to sign in'))
          .fontSize(11)
          .fontColor('#98A2B3')
          .margin({ top: 4 })
        Text(uiStatusText(this.downloadSummary))
          .fontSize(11)
          .fontColor('#98A2B3')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .backgroundColor('#F8FAFC')
    }
    .width(248)
    .height('100%')
    .backgroundColor(Color.White)
  }
}

@Component
struct DrawerHeader {
  signedIn: boolean = false;

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.signedIn ? 'EH' : '?')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2F6F8F')
            .textAlign(TextAlign.Center)
            .width(52)
            .height(52)
            .backgroundColor(Color.White)
            .borderRadius(26)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('EhViewer')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.signedIn ? uiText('Signed in') : uiText('Guest mode'))
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 20 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor('#2F6F8F')
  }
}

@Component
struct DrawerRow {
  item: DrawerItem = { route: GalleryRoute.Home, title: '', icon: '', subtitle: '' };
  selected: boolean = false;
  onTapItem: () => void = () => {};

  build() {
    Row() {
      Column()
        .width(3)
        .height(32)
        .borderRadius(2)
        .backgroundColor(this.selected ? '#2F6F8F' : 'transparent')
        .margin({ right: 10 })

      Text(this.item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selected ? '#2F6F8F' : '#6B8FAA')
        .textAlign(TextAlign.Center)
        .width(34)
        .height(34)
        .backgroundColor(this.selected ? '#D6EBF5' : '#F4F7FA')
        .borderRadius(10)

      Column() {
        Text(uiText(this.item.title))
          .fontSize(14)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selected ? '#2F6F8F' : '#2D3A45')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(uiText(this.item.subtitle))
          .fontSize(11)
          .fontColor('#98A2B3')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 8, right: 14, top: 8, bottom: 8 })
    .backgroundColor(this.selected ? '#F0F8FC' : Color.White)
    .onClick(() => {
      this.onTapItem();
    })
  }
}

@Component
struct GalleryListScene {
  private client: EhHttpClient = new EhHttpClient();

  sceneTitle: string = 'Homepage';
  listMode: string = 'Search';
  sourceRoute: GalleryRoute = GalleryRoute.Home;
  follow: string = '';
  initialKeyword: string = '';
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  onMenu: () => void = () => {};

  @State keyword: string = '';
  @State statusText: string = 'Loading galleries...';
  @State requestUrl: string = '';
  @State activeSite: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State totalPages: number = 0;
  @State resultCount: string = '';
  @State galleries: GalleryInfo[] = [];
  @State hasFirstRefresh: boolean = false;
  @State searchActive: boolean = false;
  @State fabExpanded: boolean = false;
  @State filterActive: boolean = false;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  aboutToAppear(): void {
    this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      });
      ehFilterStore.load(context).catch(() => {});
    }
    this.firstRefresh();
    activeBackHandler = () => this.handleSystemBack();
  }

  aboutToDisappear(): void {
    activeBackHandler = null;
  }

  private handleSystemBack(): boolean {
    if (this.showReader) {
      this.closeReader();
      return true;
    }
    if (this.showComments) {
      this.closeComments();
      return true;
    }
    if (this.showDetail) {
      this.closeDetail();
      return true;
    }
    return false;
  }

  private firstRefresh(): void {
    if (this.hasFirstRefresh) {
      return;
    }
    this.hasFirstRefresh = true;
    this.loadRemote(0);
  }

  private loadRemote(pageIndex: number): void {
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    this.resultCount = '';
    this.galleries = [];
    this.isLoadingMore = false;
    this.renderVersion++;
    this.closeDetail();
    const request = this.loadRoutePageWithFallback(pageIndex);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.resultCount = result.resultCount;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
    });
  }

  private loadAppendPage(): void {
    if (this.isLoadingMore) {
      return;
    }
    // Only stop if we have confirmed total page count AND already at the last page
    if (this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;
    this.renderVersion++;

    this.loadRoutePageWithFallback(nextPage).then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      if (newGalleries.length === 0) {
        // Empty page = reached the end even if we don't know total
        this.statusText = uiText('All pages loaded');
        this.isLoadingMore = false;
        this.renderVersion++;
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.isLoadingMore = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.renderVersion++;
    });
  }

  private loadRoutePageWithFallback(pageIndex: number): Promise<GalleryListLoadResult> {
    const primarySite = effectiveListSite(this.sourceRoute);
    this.activeSite = primarySite;
    return this.loadRoutePage(pageIndex, primarySite).then((primary: GalleryListLoadResult) => {
      if (!shouldRetryGalleryListOnE(primary, primarySite, this.sourceRoute)) {
        this.activeSite = primarySite;
        return primary;
      }

      return this.loadRoutePage(pageIndex, GallerySite.E).then((fallback: GalleryListLoadResult) => {
        if (fallback.ok || fallback.galleries.length > 0) {
          this.activeSite = GallerySite.E;
          return withGalleryListMessage(fallback,
            fallback.message + ' (ExHentai returned an empty list, retried on E-Hentai)');
        }

        this.activeSite = primarySite;
        return withGalleryListMessage(primary, primary.message + '; E-Hentai fallback: ' + fallback.message);
      }).catch((error: Error) => {
        this.activeSite = primarySite;
        return withGalleryListMessage(primary, primary.message + '; E-Hentai fallback failed: ' + error.message);
      });
    });
  }

  private loadRoutePage(pageIndex: number, site: GallerySite): Promise<GalleryListLoadResult> {
    if (this.sourceRoute === GalleryRoute.Favorites) {
      const builder = new FavListUrlBuilder();
      builder.keyword = this.keyword;
      builder.index = pageIndex;
      this.requestUrl = builder.build(site);
      return this.client.loadFavoritesList(builder, site);
    }

    const builder = new ListUrlBuilder();
    builder.keyword = routeUsesKeyword(this.sourceRoute) ? this.keyword : '';
    builder.pageIndex = pageIndex;
    const routeMode = this.useForcedMode ? this.forcedMode : listModeForRoute(this.sourceRoute);
    builder.mode = this.filterActive && builder.keyword.trim().length > 0 ? ListMode.Filter : routeMode;
    builder.follow = this.follow;
    this.requestUrl = builder.build(site);
    return this.client.loadGalleryList(builder, site);
  }

  private loadPreviousPage(): void {
    if (this.pageIndex > 0) {
      this.loadRemote(this.pageIndex - 1);
    }
  }

  private loadNextPage(): void {
    if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
      this.loadRemote(this.pageIndex + 1);
    }
  }

  private toggleSearchBar(): void {
    this.searchActive = !this.searchActive;
  }

  private applySearch(): void {
    this.searchActive = false;
    this.fabExpanded = false;
    this.loadRemote(0);
  }

  private toggleFilter(): void {
    this.filterActive = !this.filterActive;
    this.fabExpanded = false;
    if (this.keyword.trim().length > 0) {
      this.loadRemote(0);
      return;
    }
    this.statusText = this.filterActive ? 'Filter mode is on; enter a keyword to apply it' : 'Filter mode is off';
  }

  private jumpGalleryPage(): void {
    this.fabExpanded = false;
    if (this.totalPages <= 1) {
      this.statusText = 'No other page to jump to';
      return;
    }
    const nextPage = this.pageIndex + 1 < this.totalPages ? this.pageIndex + 1 : 0;
    this.loadRemote(nextPage);
  }

  private openRandomGallery(): void {
    this.fabExpanded = false;
    if (this.galleries.length === 0) {
      this.statusText = 'Random needs a loaded gallery list';
      return;
    }
    const index = Math.floor(Math.random() * this.galleries.length);
    this.loadDetail(this.galleries[index]);
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.showDetail = true;
    this.detail = createDetailFromGallery(gallery);
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, this.activeSite, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, this.activeSite)).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, this.activeSite));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, this.activeSite));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      this.activeSite).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.activeSite);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  build() {
    Column() {
      if (this.showReader) {
        ReaderScene({
          renderVersion: this.renderVersion,
          page: this.readerPage,
          statusText: this.readerStatus,
          pageIndex: this.readerPreviewIndex,
          totalPages: this.detail.previewSet.length,
          onBack: () => {
            this.closeReader();
          },
          onPrev: () => {
            this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
          },
          onNext: () => {
            this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
          },
          onJump: (index: number) => {
            this.loadReaderPageByIndex(index);
          },
          onRetry: () => {
            this.loadReaderPageByIndex(this.readerPreviewIndex);
          }
        })
          .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.showComments) {
        CommentsScene({
          renderVersion: this.renderVersion,
          comments: this.detail.comments,
          galleryTitle: galleryDisplayTitle(this.detail),
          onBack: () => {
            this.closeComments();
          }
        })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.showDetail) {
        GalleryDetailScene({
          renderVersion: this.renderVersion,
          detail: this.detail,
          isFavorited: this.detail.isFavorited,
          statusText: this.detailStatus,
          requestUrl: this.detailRequestUrl,
          downloadText: this.detailDownloadText,
          onBack: () => {
            this.closeDetail();
          },
          onDownload: () => {
            this.toggleDownloadDetail();
          },
          onRead: () => {
            this.readDetail();
          },
          onSelectPreview: (preview: GalleryPreview) => {
            this.loadReaderPage(preview);
          },
          onComments: () => {
            this.openComments();
          },
          onFavorite: () => {
            this.toggleFavoriteDetail();
          },
          onShare: () => {
            this.shareDetail();
          },
          initialDetailScrollOffset: this.detailScrollOffset,
          onDetailScrollUpdate: (offset: number) => {
            this.detailScrollOffset = offset;
          }
        })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else {
        GalleryListContent({
          renderVersion: this.renderVersion,
          sceneTitle: this.sceneTitle,
          listMode: this.listMode,
          keyword: this.keyword,
          searchTitle: gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive),
          searchActive: this.searchActive,
          actionsExpanded: this.fabExpanded,
          filterActive: this.filterActive,
          canJump: this.totalPages > 1,
          canRandom: this.galleries.length > 0,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          isLoadingMore: this.isLoadingMore,
          galleries: this.galleries,
          onKeywordChange: (value: string) => {
            this.keyword = value;
          },
          onMenu: () => {
            this.onMenu();
          },
          onToggleSearch: () => {
            this.toggleSearchBar();
          },
          onSearch: () => {
            this.applySearch();
          },
          onRefresh: () => {
            this.loadRemote(0);
          },
          onLoadMore: () => {
            this.loadAppendPage();
          },
          onToggleActions: () => {
            this.fabExpanded = !this.fabExpanded;
          },
          onFilter: () => {
            this.toggleFilter();
          },
          onJump: () => {
            this.jumpGalleryPage();
          },
          onRandom: () => {
            this.openRandomGallery();
          },
          onSelectGallery: (gallery: GalleryInfo) => {
            this.loadDetail(gallery);
          },
          initialScrollOffset: this.listScrollOffset,
          onScrollUpdate: (offset: number) => {
            this.listScrollOffset = offset;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct GalleryListContent {
  @Prop renderVersion: number = 0;
  @Prop sceneTitle: string = '';
  @Prop listMode: string = '';
  @Prop keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop searchActive: boolean = false;
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop galleries: GalleryInfo[] = [];
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onToggleSearch: () => void = () => {};
  onSearch: () => void = () => {};
  onRefresh: () => void = () => {};
  onLoadMore: () => void = () => {};
  onToggleActions: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRandom: () => void = () => {};
  onSelectGallery: (gallery: GalleryInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {};
  private listScroller: Scroller = new Scroller();
  private loadMorePending: boolean = false;

  private triggerLoadMoreIfNear(last: number): void {
    if (this.isLoadingMore || this.loadMorePending) {
      return;
    }
    if (this.galleries.length > 0 && last >= this.galleries.length - 6) {
      this.loadMorePending = true;
      this.onLoadMore();
      // Reset local guard after one frame so rapid scroll events don't queue duplicates
      setTimeout(() => { this.loadMorePending = false; }, 500);
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        SearchBarCard({
          keyword: this.keyword,
          title: this.searchTitle,
          searchActive: this.searchActive,
          filterActive: this.filterActive,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          onKeywordChange: this.onKeywordChange,
          onMenu: this.onMenu,
          onToggleSearch: this.onToggleSearch,
          onSearch: this.onSearch
        })

        Grid(this.listScroller) {
          ForEach(this.galleries, (gallery: GalleryInfo) => {
            GridItem() {
              if (galleryListMode() === 'Thumb') {
                GalleryThumbCard({ gallery: gallery })
                  .onClick(() => { this.onSelectGallery(gallery); })
              } else {
                GalleryListRow({ gallery: gallery })
                  .onClick(() => { this.onSelectGallery(gallery); })
              }
            }
          }, (gallery: GalleryInfo) => gallery.gid.toString() + ':' + this.renderVersion.toString())
        }
        .columnsTemplate(galleryListMode() === 'Thumb' ? 'repeat(auto-fit, 120vp)' : 'repeat(auto-fit, 320vp)')
        .columnsGap(galleryListMode() === 'Thumb' ? 6 : 8)
        .rowsGap(galleryListMode() === 'Thumb' ? 6 : 8)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, top: 8, bottom: 0 })
        .onAppear(() => {
          if (this.initialScrollOffset > 0) {
            this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
          }
        })
        .onScrollStop(() => {
          this.onScrollUpdate(this.listScroller.currentOffset().yOffset);
        })
        .onScrollIndex((first: number, last: number) => {
          this.triggerLoadMoreIfNear(last);
        })

        if (this.isLoadingMore) {
          Row() {
            LoadingProgress().width(20).height(20).color('#9BB8CB')
            Text(uiText('Loading...')).fontSize(12).fontColor('#9BB8CB').margin({ left: 6 })
          }
          .width('100%')
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F3F5F7')
        }
      }
      .width('100%')
      .height('100%')

      QuickActionColumn({
        expanded: this.actionsExpanded,
        filterActive: this.filterActive,
        canJump: this.canJump,
        canRandom: this.canRandom,
        onToggle: this.onToggleActions,
        onFilter: this.onFilter,
        onJump: this.onJump,
        onRefresh: this.onRefresh,
        onRandom: this.onRandom
      })
        .margin({ right: 18, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}

@Component
struct SearchBarCard {
  @Prop keyword: string = '';
  @Prop title: string = '';
  @Prop searchActive: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onToggleSearch: () => void = () => {};
  onSearch: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .onClick(() => {
          this.onMenu();
        })

        Stack({ alignContent: Alignment.BottomStart }) {
          TextInput({ text: this.keyword, placeholder: this.title.length === 0 ? uiText('Search galleries') : uiText(this.title) })
            .height(38)
            .width('100%')
            .backgroundColor(Color.White)
            .borderRadius(19)
            .placeholderColor('rgba(47,111,143,0.5)')
            .fontColor('#17202A')
            .caretColor('#2F6F8F')
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
          if (this.filterActive) {
            Text(uiText('Filter mode'))
              .fontSize(9)
              .fontColor(Color.White)
              .backgroundColor('rgba(255,255,255,0.3)')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 10, bottom: 6 })
          }
        }
        .height(38)
        .layoutWeight(1)
        .margin({ left: 10 })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .margin({ left: 10 })
        .onClick(() => {
          this.onSearch();
        })
      }
      .width('100%')
      .height(62)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

      if (this.statusText.length > 0) {
        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.75)')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(26)
        .padding({ left: 16, right: 14 })
        .backgroundColor('rgba(0,0,0,0.12)')
      }
    }
    .width('100%')
    .backgroundColor('#2F6F8F')
  }
}

@Component
struct QuickActionColumn {
  @Prop expanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  onToggle: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRefresh: () => void = () => {};
  onRandom: () => void = () => {};

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          ActionBubble({
            label: this.filterActive ? uiText('Filter On') : uiText('Filter'),
            symbolIcon: $r('sys.symbol.magnifyingglass'),
            isEnabled: true,
            onTapAction: () => {
              this.onFilter();
            }
          })
          ActionBubble({
            label: uiText('Jump'),
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: this.canJump,
            onTapAction: () => {
              this.onJump();
            }
          })
          ActionBubble({
            label: uiText('Refresh'),
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            onTapAction: () => {
              this.onRefresh();
            }
          })
          ActionBubble({
            label: uiText('Random'),
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: this.canRandom,
            onTapAction: () => {
              this.onRandom();
            }
          })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ bottom: 10 })
      }

      ActionBubble({
        label: '',
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        onTapAction: () => {
          this.onToggle();
        }
      })
    }
    .alignItems(HorizontalAlign.End)
  }
}

@Component
struct ActionBubble {
  @Prop label: string = '';
  @Prop symbolIcon: Resource = $r('sys.symbol.plus');
  @Prop isEnabled: boolean = true;
  primary: boolean = false;
  onTapAction: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.symbolIcon)
          .fontSize(this.primary ? 26 : 20)
          .fontColor([this.isEnabled ? Color.White : '#A0BFCC'])
      }
      .width(this.primary ? 54 : 44)
      .height(this.primary ? 54 : 44)
      .enabled(this.isEnabled)
      .backgroundColor(this.isEnabled ? (this.primary ? '#2F6F8F' : '#5A8FA8') : '#A8C0CC')
      .shadow({ radius: this.primary ? 14 : 8, color: '#33000000', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        this.onTapAction();
      })

      if (!this.primary && this.label.length > 0) {
        Text(this.label)
          .fontSize(10)
          .fontColor('#2F6F8F')
          .textAlign(TextAlign.Center)
          .backgroundColor('#DEEAF2')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
struct GalleryListRow {
  gallery: GalleryInfo = createEmptyGallery();

  build() {
    Row() {
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: galleryThumbHeight()
      })

      Column() {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(galleryListMode() === 'Thumb' ? 14 : 15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .maxLines(galleryListMode() === 'Extended' ? 3 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (galleryListMode() !== 'Thumb') {
          Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ? uiText('unknown uploader') :
            this.gallery.uploader)
            .fontSize(12)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
        }

        Blank()

        Row() {
          CategoryBadge({ category: this.gallery.category })
          Blank()
          if (showGalleryPages()) {
            Text(this.gallery.pages.toString() + 'p')
              .fontSize(12)
              .fontColor('#667085')
          }
          Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
            .fontSize(12)
            .fontColor('#98A2B3')
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        if (galleryListMode() !== 'Thumb') {
          Rating({ rating: this.gallery.rating, indicator: true })
            .stars(5)
            .stepSize(0.5)
            .height(12)
            .width(60)
            .margin({ top: 2 })
        }

        if (galleryListMode() === 'Extended' && this.gallery.simpleTags !== undefined && this.gallery.simpleTags.length > 0) {
          Text(galleryTagPreview(this.gallery))
            .fontSize(11)
            .fontColor('#40566F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
      }
      .height(galleryRowHeight())
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
struct GalleryThumb {
  url: string = '';
  widthValue: number = 86;
  heightValue: number = 118;

  @State localUrl: string = '';
  @State loadFailed: boolean = false;

  aboutToAppear(): void {
    if (this.url.length > 0) {
      this.cacheThumb();
    } else {
      this.loadFailed = true;
    }
  }

  private cacheThumb(): void {
    cacheThumbnailImage(this.url, (path: string) => {
      this.localUrl = readerLocalImageSource(path);
    });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#E7ECF1')
        .borderRadius(4)

      if (this.loadFailed) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor(['#9BB8CB'])
          Text('EH')
            .fontSize(10)
            .fontColor('#9BB8CB')
        }
        .justifyContent(FlexAlign.Center)
      } else if (this.localUrl.length > 0) {
        Image(this.localUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
          .onError(() => {
            this.loadFailed = true;
          })
      } else {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#9BB8CB')
      }
    }
    .width(this.widthValue > 0 ? this.widthValue : '100%')
    .height(this.heightValue > 0 ? this.heightValue : '100%')
  }
}

@Component
struct GalleryThumbCard {
  gallery: GalleryInfo = createEmptyGallery();

  build() {
    Column() {
      // 3:4 portrait ratio image area that fills column width
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: 0,
        heightValue: 0
      })
        .width('100%')
        .aspectRatio(0.75)

      Column() {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          CategoryBadge({ category: this.gallery.category })
          Blank()
          Text(this.gallery.pages.toString() + 'p')
            .fontSize(11)
            .fontColor('#98A2B3')
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .alignItems(HorizontalAlign.Start)
    }
    .backgroundColor(Color.White)
    .borderRadius(6)
    .clip(true)
  }
}

@Component
struct CategoryBadge {
  category: number = GalleryCategory.Unknown;

  build() {
    Text(categoryName(this.category))
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(3)
  }
}

@Component
struct GalleryDetailScene {
  @Prop renderVersion: number = 0;
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isFavorited: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop downloadText: string = 'Download';
  onBack: () => void = () => {};
  onDownload: () => void = () => {};
  onRead: () => void = () => {};
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
  onComments: () => void = () => {};
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  initialDetailScrollOffset: number = 0;
  onDetailScrollUpdate: (offset: number) => void = () => {};
  private detailScroller: Scroller = new Scroller();
  private client: EhHttpClient = new EhHttpClient();
  @State showRatingDialog: boolean = false;
  @State pendingRating: number = 0;

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.onBack();
        })
        Text(galleryDisplayTitle(this.detail))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor('#0A6B45')
          .width('100%')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#F0FBF6')
      }

      List({ space: 0, scroller: this.detailScroller }) {
        ListItem() {
          DetailHeader({
            detail: this.detail,
            downloadText: this.downloadText,
            onDownload: this.onDownload,
            onRead: this.onRead
          })
        }
        ListItem() {
          DetailInfoBlock({ detail: this.detail, requestUrl: this.requestUrl })
        }
        ListItem() {
          DetailActions({
            detail: this.detail,
            isFavorited: this.isFavorited,
            onFavorite: this.onFavorite,
            onShare: this.onShare,
            onTorrent: () => {},
            onArchive: () => {}
          })
        }
        ListItem() {
          DetailTags({ tags: this.detail.tags })
        }
        ListItem() {
          DetailPreviews({
            previews: this.detail.previewSet,
            previewPages: this.detail.previewPages,
            onSelectPreview: this.onSelectPreview
          })
        }
        ListItem() {
          DetailComments({
            comments: this.detail.comments,
            onComments: this.onComments
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAppear(() => {
        if (this.initialDetailScrollOffset > 0) {
          this.detailScroller.scrollTo({ xOffset: 0, yOffset: this.initialDetailScrollOffset });
        }
      })
      .onScrollStop(() => {
        this.onDetailScrollUpdate(this.detailScroller.currentOffset().yOffset);
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct DetailHeader {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop downloadText: string = 'Download';
  onDownload: () => void = () => {};
  onRead: () => void = () => {};

  build() {
    Column() {
      Row() {
        GalleryThumb({
          url: this.detail.thumb === undefined ? '' : this.detail.thumb,
          widthValue: galleryThumbWidth(),
          heightValue: galleryThumbHeight()
        })
        Column() {
          Text(galleryDisplayTitle(this.detail))
            .fontSize(detailTitleFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(detailTitleMaxLines())
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detail.uploader === undefined || this.detail.uploader.length === 0 ? uiText('unknown uploader') :
            this.detail.uploader)
            .fontSize(12)
            .fontColor('#DDE7F2')
            .margin({ top: 8 })
          CategoryBadge({ category: this.detail.category })
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')

      Row() {
        HeaderActionButton({
          symbolIcon: this.downloadText === 'Queued' ? $r('sys.symbol.checkmark') : $r('sys.symbol.save'),
          text: uiText(this.downloadText),
          onTap: this.onDownload
        })
          .layoutWeight(1)
        Column()
          .width(1)
          .height(32)
          .backgroundColor('#5E8EA5')
        HeaderActionButton({
          symbolIcon: $r('sys.symbol.play_fill'),
          text: uiText('Read'),
          accent: true,
          onTap: this.onRead
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .margin({ top: 16 })
      .padding(4)
      .backgroundColor('#225A73')
      .borderRadius(6)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2F6F8F')
  }
}

@Component
struct HeaderActionButton {
  symbolIcon: Resource = $r('sys.symbol.play_fill');
  text: string = '';
  accent: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      SymbolGlyph(this.symbolIcon)
        .fontSize(22)
        .fontColor([this.accent ? '#17202A' : Color.White])
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent ? '#17202A' : Color.White)
        .margin({ left: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(48)
    .width('100%')
    .backgroundColor(this.accent ? '#F7C948' : '#2B6B87')
    .borderRadius(4)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
struct DetailInfoBlock {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop requestUrl: string = '';

  build() {
    Column() {
      Text(uiText('Information'))
        .fontSize(detailHeadingFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      InfoRow({ label: uiText('Posted'), value: this.detail.posted === undefined ? '' : this.detail.posted })
      InfoRow({ label: uiText('Parent'), value: this.detail.parent })
      InfoRow({ label: uiText('Visible'), value: this.detail.visible })
      InfoRow({ label: uiText('Language'), value: this.detail.language })
      InfoRow({ label: uiText('File Size'), value: this.detail.size })
      InfoRow({ label: uiText('Length'), value: this.detail.pages.toString() + (shouldUseChineseUi() ? ' 页' : ' pages') })
      InfoRow({ label: uiText('Rating'), value: ratingText(this.detail.rating) + ' / ' + this.detail.ratingCount.toString() })
      InfoRow({ label: uiText('Favorited'), value: this.detail.favoriteCount.toString() })
      if (this.requestUrl.length > 0) {
        InfoRow({ label: 'URL', value: this.requestUrl })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
struct InfoRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor('#667085')
        .width(86)
      Text(this.value.length === 0 ? '-' : this.value)
        .fontSize(12)
        .fontColor('#17202A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }
}

@Component
struct DetailActions {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isFavorited: boolean = false;
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  onTorrent: () => void = () => {};
  onArchive: () => void = () => {};

  build() {
    Scroll() {
      Row() {
        DetailActionItem({
          symbolIcon: $r('sys.symbol.heart'),
          label: this.isFavorited ? uiText('Favorited') : uiText('Favorite'),
          isActive: this.detail.gid > 0,
          isFilled: this.isFavorited,
          onTap: this.onFavorite
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.share'),
          label: uiText('Share'),
          isActive: this.detail.gid > 0,
          onTap: this.onShare
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.save'),
          label: this.detail.torrentCount > 0 ?
            'Torrent (' + this.detail.torrentCount.toString() + ')' : 'Torrent',
          isActive: this.detail.torrentCount > 0 && this.detail.torrentUrl.length > 0,
          onTap: this.onTorrent
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.doc_plaintext'),
          label: uiText('Archive'),
          isActive: this.detail.archiveUrl.length > 0,
          onTap: this.onArchive
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(Color.White)
  }
}
@Component
struct DetailActionItem {
  symbolIcon: Resource = $r('sys.symbol.heart');
  label: string = '';
  isActive: boolean = true;
  isFilled: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      SymbolGlyph(this.symbolIcon)
        .fontSize(26)
        .fontColor([this.isActive ? (this.isFilled ? '#E05C4B' : '#2F6F8F') : '#B8CDD8'])
      Text(this.label)
        .fontSize(11)
        .fontColor(this.isActive ? '#2F6F8F' : '#B8CDD8')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(72)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.isActive) {
        this.onTap();
      }
    })
  }
}

@Component
struct DetailTags {
  @Prop tags: GalleryTagGroup[] = [];

  build() {
    Column() {
      Text(uiText('Tags'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      if (this.tags.length === 0) {
        Text(uiText('No tags parsed'))
          .fontSize(12)
          .fontColor('#667085')
          .margin({ top: 8 })
      } else {
        ForEach(this.tags, (group: GalleryTagGroup) => {
          TagGroupRow({ namespace: group.namespace, tags: group.tags })
        }, (group: GalleryTagGroup) => group.namespace)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
struct TagGroupRow {
  namespace: string = '';
  tags: string[] = [];

  build() {
    Row() {
      Text(this.namespace)
        .fontSize(12)
        .fontColor('#40566F')
        .width(86)
      Text(this.tags.join(', '))
        .fontSize(12)
        .fontColor('#667085')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }
}

@Component
struct DetailPreviews {
  @Prop previews: GalleryPreview[] = [];
  @Prop previewPages: number = 0;
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Column() {
      Text(uiText('Previews'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      Text(shouldUseChineseUi() ? this.previews.length.toString() + ' 个缩略图 / ' + this.previewPages.toString() + ' 页' :
        this.previews.length.toString() + ' thumbnails / ' + this.previewPages.toString() + ' pages')
        .fontSize(12)
        .fontColor('#667085')
        .width('100%')
        .margin({ top: 6, bottom: 8 })
      ForEach(this.previews.slice(0, 12), (preview: GalleryPreview) => {
        PreviewRow({
          preview: preview,
          onSelectPreview: (selected: GalleryPreview) => {
            this.onSelectPreview(selected);
          }
        })
      }, (preview: GalleryPreview) => preview.index.toString())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
struct PreviewRow {
  preview: GalleryPreview = createEmptyPreview();
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Row() {
      GalleryThumb({
        url: this.preview.imageUrl,
        widthValue: 74,
        heightValue: 54
      })
      Column() {
        Text(uiText('Page') + ' ' + (this.preview.index + 1).toString())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(this.preview.pageUrl)
          .fontSize(11)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .margin({ top: 8 })
    .onClick(() => {
      this.onSelectPreview(this.preview);
    })
  }
}

function stripHtml(html: string): string {
  let text = html
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
  return text;
}

@Component
struct DetailComments {
  @Prop comments: GalleryComment[] = [];
  onComments: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(uiText('Comments'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .layoutWeight(1)
        if (this.comments.length > 0) {
          Text(uiText('See all') + ' (' + this.comments.length.toString() + ')')
            .fontSize(13)
            .fontColor('#2F6F8F')
            .onClick(() => {
              this.onComments();
            })
        } else {
          Text('0 ' + uiText('comments'))
            .fontSize(13)
            .fontColor('#667085')
        }
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.comments.length === 0) {
        Text(uiText('No comments'))
          .fontSize(13)
          .fontColor('#667085')
      } else {
        ForEach(this.comments.slice(0, 3), (comment: GalleryComment) => {
          Column() {
            Row() {
              Text(comment.user.length > 0 ? comment.user : uiText('Anonymous'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#17202A')
                .layoutWeight(1)
              Text(comment.posted)
                .fontSize(11)
                .fontColor('#667085')
            }
            .width('100%')
            .margin({ bottom: 4 })

            Text(stripHtml(comment.content))
              .fontSize(13)
              .fontColor('#333333')
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(10)
          .margin({ bottom: 6 })
          .backgroundColor('#F5F8FA')
          .borderRadius(6)
        }, (comment: GalleryComment) => comment.id)

        if (this.comments.length > 3) {
          Text(uiText('View all') + ' ' + this.comments.length.toString() + ' ' + uiText('comments') + ' →')
            .fontSize(13)
            .fontColor('#2F6F8F')
            .margin({ top: 6 })
            .onClick(() => {
              this.onComments();
            })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
struct CommentsScene {
  @Prop renderVersion: number = 0;
  @Prop comments: GalleryComment[] = [];
  @Prop galleryTitle: string = '';
  onBack: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.onBack();
        })
        Column() {
          Text(uiText('Comments'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
          Text(this.galleryTitle)
            .fontSize(11)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        Text(this.comments.length.toString() + ' ' + uiText('total'))
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })
      .backgroundColor(Color.White)

      if (this.comments.length === 0) {
        PlaceholderScene({
          title: 'Comments',
          detail: 'No comments for this gallery.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.comments, (comment: GalleryComment) => {
            ListItem() {
              Column() {
                Row() {
                  Text(comment.user.length > 0 ? comment.user : uiText('Anonymous'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#17202A')
                    .layoutWeight(1)
                  if (comment.score !== 0) {
                    Text((comment.score > 0 ? '+' : '') + comment.score.toString())
                      .fontSize(12)
                      .fontColor(comment.score > 0 ? '#0A6B45' : '#B03060')
                      .margin({ left: 8 })
                  }
                }
                .width('100%')
                .margin({ bottom: 4 })

                Text(comment.posted)
                  .fontSize(11)
                  .fontColor('#667085')
                  .margin({ bottom: 8 })

                Text(stripHtml(comment.content))
                  .fontSize(14)
                  .fontColor('#17202A')
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(Color.White)
            }
          }, (comment: GalleryComment) => comment.id)
          ListItem() {
            Divider()
              .height(1)
              .color('#F0F0F0')
          }
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

@Component
struct ReaderScene {
  @Prop renderVersion: number = 0;
  @Prop page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop pageIndex: number = 0;
  @Prop totalPages: number = 0;
  onBack: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onJump: (index: number) => void = () => {};
  onRetry: () => void = () => {};

  @State zoomPercent: number = 100;
  @State fitMode: string = 'Fit width';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State controlsVisible: boolean = false;

  aboutToAppear(): void {
    this.fitMode = ehSettingsStore.getValue('page_scaling', 'Fit width');
    this.controlsVisible = false;
    this.applyReaderWindowSettings();
  }

  aboutToDisappear(): void {
    this.restoreWindowSettings();
  }

  private restoreWindowSettings(): void {
    const win = AppStorage.get<window.Window>('mainWindow');
    if (win === undefined) {
      return;
    }
    try {
      win.setWindowKeepScreenOn(false).catch(() => {});
    } catch (e) {}
    try {
      win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch(() => {});
    } catch (e) {}
  }

  private applyReaderWindowSettings(): void {
    const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    const orientation = ehSettingsStore.getValue('screen_rotation', 'System');
    const win = AppStorage.get<window.Window>('mainWindow');
    if (win !== undefined) {
      try {
        win.setWindowKeepScreenOn(keepOn).catch(() => {});
      } catch (e) {}
      try {
        let o: window.Orientation = window.Orientation.UNSPECIFIED;
        if (orientation === 'Portrait') {
          o = window.Orientation.PORTRAIT;
        } else if (orientation === 'Landscape') {
          o = window.Orientation.LANDSCAPE;
        }
        win.setPreferredOrientation(o).catch(() => {});
      } catch (e) {}
    }
  }

  private zoomOut(): void {
    this.zoomPercent = Math.max(50, this.zoomPercent - 25);
  }

  private zoomIn(): void {
    this.zoomPercent = Math.min(300, this.zoomPercent + 25);
  }

  private resetZoom(): void {
    this.zoomPercent = 100;
  }

  private cycleFitMode(): void {
    const next = nextOption(this.fitMode, ['Fit width', 'Fit height', 'Original', 'Smart fit']);
    this.fitMode = next;
    ehSettingsStore.setValue('page_scaling', next);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
  }

  private tapLeftPageArea(): void {
    if (readerIsRightToLeft()) {
      if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
        this.onNext();
      }
      return;
    }

    if (this.pageIndex > 0) {
      this.onPrev();
    }
  }

  private tapRightPageArea(): void {
    if (readerIsRightToLeft()) {
      if (this.pageIndex > 0) {
        this.onPrev();
      }
      return;
    }

    if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
      this.onNext();
    }
  }

  private toggleControls(): void {
    this.controlsVisible = !this.controlsVisible;
  }

  private jumpTo(value: number): void {
    if (this.totalPages <= 0) {
      return;
    }
    const target = Math.max(0, Math.min(this.totalPages - 1, Math.round(value)));
    if (target !== this.pageIndex) {
      this.onJump(target);
    }
  }

  private progressText(): string {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    return (this.pageIndex + 1).toString() + '/' + total.toString();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          if (readerDisplayImageUrl(this.page, this.preferOriginal).length > 0) {
            Image(readerDisplayImageUrl(this.page, this.preferOriginal))
              .width(readerFullImageWidth(this.zoomPercent))
              .height(readerFullImageHeight(this.zoomPercent))
              .objectFit(readerImageFit(this.fitMode))
              .backgroundColor('#050608')
          } else {
            Text(this.statusText.indexOf('failed') >= 0 || this.statusText.indexOf('Failed') >= 0 ?
              uiText('Image page failed to load') : uiText('Image page is loading'))
              .fontSize(16)
              .fontColor('#98A2B3')
          }

          Row() {
            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.tapLeftPageArea();
            })

            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.toggleControls();
            })

            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.tapRightPageArea();
            })
          }
          .width('100%')
          .height('100%')

          if (!this.controlsVisible && readerShowProgress()) {
            Text(this.progressText())
              .fontSize(12)
              .fontColor('#F2F4F7')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000')
              .borderRadius(12)
              .position({ x: 12, y: 12 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#050608')
      }
      .width('100%')
      .height('100%')

      if (this.controlsVisible) {
        Column() {
          Row() {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .backgroundColor('#CC111827')
            .onClick(() => {
              this.onBack();
            })
            Text(uiStatusText(this.statusText))
              .fontSize(12)
              .fontColor('#E5E7EB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 10 })
              .layoutWeight(1)
            if (readerShowClock()) {
              Text(readerClockText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
            if (readerShowProgress()) {
              Text(this.progressText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 10 })
          .backgroundColor('#99000000')

          Blank()
            .layoutWeight(1)

          if (this.showInfo) {
            Column() {
              InfoRow({ label: uiText('Page URL'), value: this.page.pageUrl })
              InfoRow({ label: uiText('Image URL'), value: this.page.imageUrl })
              InfoRow({ label: uiText('Original'), value: this.page.originImageUrl })
              InfoRow({ label: uiText('Show Key'), value: this.page.showKey })
              InfoRow({ label: uiText('Retry Key'), value: this.page.skipHathKey })
              InfoRow({ label: uiText('Fit'), value: uiValue(this.fitMode) + ', zoom ' + this.zoomPercent.toString() + '%' })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#EEFFFFFF')
          }

          Column() {
            Row() {
              Text((this.pageIndex + 1).toString())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .width(42)
              Slider({
                value: this.pageIndex,
                min: 0,
                max: Math.max(0, this.totalPages - 1),
                step: 1
              })
                .layoutWeight(1)
                .enabled(this.totalPages > 1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.jumpTo(value);
                  }
                })
              Text((this.totalPages <= 0 ? 1 : this.totalPages).toString())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .textAlign(TextAlign.End)
                .width(42)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 8 }) {
              ReaderNavButton({
                text: uiText('Previous'),
                active: this.pageIndex > 0,
                onTap: this.onPrev
              })
                .layoutWeight(1)
              ReaderNavButton({
                text: uiText('Next'),
                active: this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages,
                onTap: this.onNext
              })
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 10 })

            Row({ space: 8 }) {
              ReaderToolButton({
                text: '-',
                active: this.zoomPercent > 50,
                onTap: () => {
                  this.zoomOut();
                }
              })
              ReaderToolButton({
                text: this.zoomPercent.toString() + '%',
                active: true,
                onTap: () => {
                  this.resetZoom();
                }
              })
              ReaderToolButton({
                text: '+',
                active: this.zoomPercent < 300,
                onTap: () => {
                  this.zoomIn();
                }
              })
              ReaderToolButton({
                text: uiValue(this.fitMode),
                active: true,
                onTap: () => {
                  this.cycleFitMode();
                }
              })
              ReaderToolButton({
                text: this.preferOriginal ? uiText('Original') : uiText('Resampled'),
                active: this.page.originImageUrl.length > 0,
                onTap: () => {
                  this.preferOriginal = !this.preferOriginal;
                }
              })
              ReaderToolButton({
                text: uiText('Info'),
                active: true,
                onTap: () => {
                  this.showInfo = !this.showInfo;
                }
              })
              ReaderToolButton({
                text: uiText('Retry'),
                active: this.page.pageUrl.length > 0,
                onTap: this.onRetry
              })
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 14 })
          .backgroundColor('#CC111827')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
  }
}

@Component
struct ReaderToolButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.text)
      .height(32)
      .fontSize(12)
      .fontColor(this.active ? Color.White : '#6B7280')
      .backgroundColor(this.active ? '#334155' : '#1F2937')
      .enabled(this.active)
      .onClick(() => {
        if (this.active) {
          this.onTap();
        }
      })
  }
}

@Component
struct ReaderNavButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.active ? Color.White : '#98A2B3')
    }
    .justifyContent(FlexAlign.Center)
    .height(42)
    .width('100%')
    .backgroundColor(this.active ? '#2F6F8F' : '#1F2937')
    .borderRadius(4)
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}

@Component
struct HistoryScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State histories: GalleryInfo[] = [];
  @State statusText: string = 'Loading history...';
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a history item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  private historyScroller: Scroller = new Scroller();
  private historyScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  aboutToAppear(): void {
    activeBackHandler = () => this.handleSystemBack();
    this.loadHistory();
  }

  aboutToDisappear(): void {
    activeBackHandler = null;
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    return false;
  }

  private loadHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' local history items';
      this.renderVersion++;
      return;
    }

    ehHistoryStore.load(context).then(() => {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' history items';
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'History load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private clearHistory(): void {
    ehHistoryStore.clear();
    this.histories = [];
    this.statusText = 'History cleared';
    this.renderVersion++;
    this.persistHistory();
  }

  private removeHistory(gallery: GalleryInfo): void {
    ehHistoryStore.removeGallery(gallery.gid);
    this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
    this.statusText = 'Removed from history: ' + gallery.title;
    this.renderVersion++;
    this.persistHistory();
  }

  private persistHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehHistoryStore.save(context).catch((error: Error) => {
      this.statusText = 'History save failed: ' + error.message;
    });
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.showDetail = true;
    this.detail = createDetailFromGallery(gallery);
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, currentGallerySite(), '').then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.loadHistory();
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a history item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
    this.loadHistory();
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, currentGallerySite())).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, currentGallerySite()));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, currentGallerySite()));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.detail.previewSet.length,
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.open_sidebar'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(38)
          .height(38)
          .backgroundColor('rgba(255,255,255,0.15)')
          .onClick(() => {
            this.onMenu();
          })
          Column() {
            Text(uiText('History'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            if (this.statusText.length > 0) {
              Text(uiStatusText(this.statusText))
                .fontSize(11)
                .fontColor('rgba(255,255,255,0.7)')
                .margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
              .fontSize(18)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor('rgba(255,255,255,0.15)')
          .onClick(() => {
            this.loadHistory();
          })
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(17)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor(this.histories.length > 0 ? 'rgba(220,60,50,0.75)' : 'rgba(255,255,255,0.1)')
          .margin({ left: 8 })
          .enabled(this.histories.length > 0)
          .onClick(() => {
            this.clearHistory();
          })
        }
        .width('100%')
        .height(60)
        .padding({ left: 14, right: 14 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#2F6F8F')

        if (this.histories.length === 0) {
          PlaceholderScene({
            title: 'History',
            detail: 'Viewed gallery details will appear here. Open a gallery from Homepage, Favorites or Top Lists to add it.'
          })
        } else {
          List({ space: 8, scroller: this.historyScroller }) {
            ForEach(this.histories, (gallery: GalleryInfo) => {
              ListItem() {
                Column() {
                  GalleryListRow({ gallery: gallery })
                    .onClick(() => {
                      this.loadDetail(gallery);
                    })
                  Row() {
                    Text(uiText('Remove'))
                      .fontSize(12)
                      .fontColor('#C33A2C')
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .onClick(() => {
                        this.removeHistory(gallery);
                      })
                    Blank()
                  }
                  .width('100%')
                  .padding({ right: 8, bottom: 6 })
                  .backgroundColor(Color.White)
                }
                .borderRadius(6)
              }
            }, (gallery: GalleryInfo) => gallery.gid.toString() + ':' + this.renderVersion.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 8, right: 8, top: 8, bottom: 12 })
          .onAppear(() => {
            if (this.historyScrollOffset > 0) {
              this.historyScroller.scrollTo({ xOffset: 0, yOffset: this.historyScrollOffset });
            }
          })
          .onScrollStop(() => {
            this.historyScrollOffset = this.historyScroller.currentOffset().yOffset;
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
struct TopListScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State statusText: string = 'Loading top lists...';
  @State requestUrl: string = '';
  @State selectedIndex: number = 0;
  @State topList: TopListDetail = createEmptyTopListDetail();
  @State showGalleryList: boolean = false;
  @State galleryListTitle: string = 'Top List';
  @State galleryListModeLabel: string = 'Top List';
  @State galleryFollow: string = '';
  @State galleryKeyword: string = '';
  @State galleryRoute: GalleryRoute = GalleryRoute.TopLists;
  @State galleryUseForcedMode: boolean = false;
  @State galleryForcedMode: ListMode = ListMode.Normal;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a ranking item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  private topListScroller: Scroller = new Scroller();
  private topListScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  aboutToAppear(): void {
    activeBackHandler = () => this.handleSystemBack();
    this.loadTopList();
  }

  aboutToDisappear(): void {
    activeBackHandler = null;
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    if (this.showGalleryList) { this.closeGalleryList(); return true; }
    return false;
  }

  private loadTopList(): void {
    this.statusText = 'Loading top lists...';
    this.renderVersion++;
    this.client.loadTopList(GallerySite.E).then((result: TopListLoadResult) => {
      this.requestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.statusText = 'Load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.topList = cloneTopListDetail(result.detail);
      this.statusText = result.message + ': ' + result.detail.lists.length.toString() + ' sections';
      if (this.selectedIndex >= result.detail.lists.length) {
        this.selectedIndex = 0;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openBucket(bucket: TopListBucket): void {
    this.galleryListTitle = 'Gallery Toplists';
    this.galleryListModeLabel = bucket.title;
    this.galleryFollow = bucket.follow;
    this.galleryKeyword = '';
    this.galleryRoute = GalleryRoute.TopLists;
    this.galleryUseForcedMode = false;
    this.showGalleryList = true;
  }

  private openTopListItem(item: TopListItem, info: TopListInfo): void {
    if (item.gid.length > 0 && item.token.length > 0) {
      this.loadDetailFromItem(item);
      return;
    }

    this.galleryListTitle = info.title;
    this.galleryListModeLabel = 'Related galleries';
    this.galleryFollow = '';
    this.galleryKeyword = item.value;
    this.galleryRoute = GalleryRoute.Home;
    this.galleryUseForcedMode = true;
    this.galleryForcedMode = info.kind === TopListKind.Uploader ? ListMode.Uploader : ListMode.Normal;
    this.showGalleryList = true;
  }

  private closeGalleryList(): void {
    this.showGalleryList = false;
    this.galleryFollow = '';
    this.galleryKeyword = '';
    this.galleryUseForcedMode = false;
  }

  private loadDetailFromItem(item: TopListItem): void {
    const gid = Number.parseInt(item.gid);
    if (Number.isNaN(gid)) {
      this.statusText = 'Invalid gallery id: ' + item.gid;
      return;
    }

    this.showDetail = true;
    const loadingDetail = createEmptyDetail();
    loadingDetail.gid = gid;
    loadingDetail.token = item.token;
    loadingDetail.title = item.value;
    this.detail = loadingDetail;
    this.detailStatus = 'Loading detail for gid ' + item.gid + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gid, item.token, 0, GallerySite.E, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a ranking item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, GallerySite.E)).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, GallerySite.E));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, GallerySite.E));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  private currentInfo(): TopListInfo {
    if (this.topList.lists.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.topList.lists.length) {
      return createEmptyTopListInfo();
    }
    return this.topList.lists[this.selectedIndex];
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.detail.previewSet.length,
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showGalleryList) {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor('#2F6F8F')
          .onClick(() => {
            this.closeGalleryList();
          })
          Text(uiText(this.galleryListTitle) + ' / ' + uiText(this.galleryListModeLabel))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })
        .backgroundColor(Color.White)

        GalleryListScene({
          sceneTitle: this.galleryListTitle,
          listMode: this.galleryListModeLabel,
          sourceRoute: this.galleryRoute,
          follow: this.galleryFollow,
          initialKeyword: this.galleryKeyword,
          useForcedMode: this.galleryUseForcedMode,
          forcedMode: this.galleryForcedMode
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.move(TransitionEdge.END)
        .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Column() {
        TopListHeader({
          title: this.topList.title.length === 0 ? uiText('Top Lists') : this.topList.title,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          onMenu: this.onMenu,
          onRefresh: () => {
            this.loadTopList();
          }
        })
          .margin({ left: 12, right: 12, top: 12, bottom: 8 })

        TopListTabs({
          lists: this.topList.lists,
          selectedIndex: this.selectedIndex,
          onSelect: (index: number) => {
            this.selectedIndex = index;
          }
        })
          .margin({ left: 12, right: 12, bottom: 8 })

        TopListBoard({
          info: this.currentInfo(),
          onOpenBucket: (bucket: TopListBucket) => {
            this.openBucket(bucket);
          },
          onOpenItem: (item: TopListItem, info: TopListInfo) => {
            this.openTopListItem(item, info);
          },
          initialScrollOffset: this.topListScrollOffset,
          onScrollUpdate: (offset: number) => {
            this.topListScrollOffset = offset;
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
struct TopListHeader {
  @Prop title: string = '';
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  onMenu: () => void = () => {};
  onRefresh: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .margin({ right: 10 })
        .onClick(() => {
          this.onMenu();
        })
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#17202A')
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.onRefresh();
        })
      }
      .width('100%')

      Text(uiStatusText(this.statusText))
        .fontSize(12)
        .fontColor('#40566F')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })

      Text(this.requestUrl.length === 0 ? uiText('Waiting for toplist.php') : this.requestUrl)
        .fontSize(11)
        .fontColor('#98A2B3')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
struct TopListTabs {
  @Prop lists: TopListInfo[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.lists, (info: TopListInfo, index: number) => {
          Button(info.title)
            .height(34)
            .fontSize(12)
            .fontColor(index === this.selectedIndex ? Color.White : '#2F6F8F')
            .backgroundColor(index === this.selectedIndex ? '#2F6F8F' : Color.White)
            .border({ width: 1, color: '#D0D5DD' })
            .onClick(() => {
              this.onSelect(index);
            })
        }, (info: TopListInfo) => info.kind.toString())
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}

@Component
struct TopListBoard {
  @Prop info: TopListInfo = createEmptyTopListInfo();
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {};
  private boardScroller: Scroller = new Scroller();

  build() {
    List({ space: 10, scroller: this.boardScroller }) {
      ForEach(this.info.buckets, (bucket: TopListBucket) => {
        ListItem() {
          TopListBucketCard({
            bucket: bucket,
            info: this.info,
            canOpenBucket: this.info.kind === TopListKind.Gallery,
            onOpenBucket: this.onOpenBucket,
            onOpenItem: this.onOpenItem
          })
        }
      }, (bucket: TopListBucket) => bucket.title)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, bottom: 14 })
    .onAppear(() => {
      if (this.initialScrollOffset > 0) {
        this.boardScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
      }
    })
    .onScrollStop(() => {
      this.onScrollUpdate(this.boardScroller.currentOffset().yOffset);
    })
  }
}

@Component
struct TopListBucketCard {
  bucket: TopListBucket = createEmptyTopListBucket();
  info: TopListInfo = createEmptyTopListInfo();
  canOpenBucket: boolean = false;
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.bucket.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canOpenBucket ? '#2F6F8F' : '#17202A')
          .layoutWeight(1)
          .decoration({ type: this.canOpenBucket ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (this.canOpenBucket) {
              this.onOpenBucket(this.bucket);
            }
          })
        Text(this.bucket.items.length.toString() + ' entries')
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.bucket.items, (item: TopListItem, index: number) => {
          TopListChip({
            item: item,
            color: topListChipColor(index),
            onTap: () => {
              this.onOpenItem(item, this.info);
            }
          })
        }, (item: TopListItem) => item.href + item.value)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
struct TopListChip {
  item: TopListItem = createEmptyTopListItem();
  color: string = '#2F6F8F';
  onTap: () => void = () => {};

  build() {
    Text(this.item.value)
      .fontSize(13)
      .fontColor(Color.White)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.color)
      .borderRadius(5)
      .onClick(() => {
        this.onTap();
      })
  }
}

@Component
struct SessionScene {
  private client: EhHttpClient = new EhHttpClient();
  private webController: webview.WebviewController = new webview.WebviewController();

  @State mode: SessionMode = SessionMode.Password;
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State memberId: string = '';
  @State passHash: string = '';
  @State igneous: string = '';
  @State signingIn: boolean = false;
  @State webCookieCaptured: boolean = false;
  @State webUrl: string = EhUrl.URL_SIGN_IN;
  @State statusText: string = 'Sign in with an E-Hentai forum account';
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    this.cookieInput = ehCookieStore.getCookieHeader();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).then(() => {
        this.cookieInput = ehCookieStore.getCookieHeader();
        this.syncCookieFieldsFromInput(this.cookieInput, false);
        this.statusText = ehCookieStore.hasCookies() ? 'Persisted Cookie loaded' : 'No Cookie saved';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
    }
  }

  private switchMode(mode: SessionMode): void {
    this.mode = mode;
    if (mode === SessionMode.Password) {
      this.statusText = 'Sign in with an E-Hentai forum account';
    } else if (mode === SessionMode.Cookie) {
      this.statusText = 'Enter ipb_member_id and ipb_pass_hash, or paste a full Cookie header';
    } else {
      this.statusText = 'Finish login in the web page; Cookie will be captured automatically';
      this.webCookieCaptured = false;
    }
  }

  private signInWithPassword(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }
    if (this.signingIn) {
      return;
    }
    if (this.username.trim().length === 0) {
      this.statusText = 'Username cannot be empty';
      return;
    }
    if (this.password.length === 0) {
      this.statusText = 'Password cannot be empty';
      return;
    }

    this.signingIn = true;
    this.statusText = 'Signing in...';
    this.client.signIn(this.username.trim(), this.password).then((result: SignInResult) => {
      this.signingIn = false;
      if (!result.ok) {
        this.statusText = 'Sign in failed: ' + result.message;
        return;
      }

      ehCookieStore.save(context).then(() => {
        this.cookieInput = ehCookieStore.getCookieHeader();
        this.statusText = result.message;
        this.onSignedIn();
      }).catch((error: Error) => {
        this.statusText = 'Signed in but Cookie save failed: ' + error.message;
      });
    }).catch((error: Error) => {
      this.signingIn = false;
      this.statusText = 'Sign in failed: ' + error.message;
    });
  }

  private prepareWebSignIn(): void {
    try {
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/');
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/');
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
    ehCookieStore.clear();
    this.webCookieCaptured = false;
    this.statusText = 'Web sign-in is ready; existing browser verification is kept';
  }

  private checkWebCookie(url: string): void {
    if (this.webCookieCaptured) {
      return;
    }

    const cookieHeader = collectWebCookies(url);
    if (cookieHeader.length > 0) {
      ehCookieStore.setCookieHeader(cookieHeader);
      this.cookieInput = ehCookieStore.getCookieHeader();
    }
    if (!hasLoginCookie(cookieHeader)) {
      this.statusText = cookieHeader.length > 0 ? 'Web verification Cookie captured; waiting for login...' :
        'Waiting for web login...';
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Web Cookie found, but context is not ready';
      return;
    }

    this.webCookieCaptured = true;
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getCookieHeader();
      this.statusText = 'Web Cookie captured';
      this.onSignedIn();
    }).catch((error: Error) => {
      this.webCookieCaptured = false;
      this.statusText = 'Web Cookie save failed: ' + error.message;
    });
  }

  private saveCookie(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }

    const cookieHeader = this.buildCookieHeader();
    if (!this.validateCookieFields()) {
      return;
    }
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getCookieHeader();
      this.statusText = ehCookieStore.hasCookies() ? 'Cookie saved' : 'Empty Cookie saved';
      if (ehCookieStore.hasCookies()) {
        this.onSignedIn();
      }
    }).catch((error: Error) => {
      this.statusText = 'Cookie save failed: ' + error.message;
    });
  }

  private buildCookieHeader(): string {
    const names: string[] = [];
    const values: string[] = [];
    absorbCookieHeaderText(this.cookieInput, names, values);
    if (this.memberId.trim().length > 0) {
      upsertCookiePair('ipb_member_id', this.memberId.trim(), names, values);
    }
    if (this.passHash.trim().length > 0) {
      upsertCookiePair('ipb_pass_hash', this.passHash.trim(), names, values);
    }
    if (this.igneous.trim().length > 0) {
      upsertCookiePair('igneous', this.igneous.trim(), names, values);
    }

    const parts: string[] = [];
    for (let i = 0; i < names.length; i++) {
      parts.push(names[i] + '=' + values[i]);
    }
    return parts.join('; ');
  }

  private syncCookieFieldsFromInput(value: string, showStatus: boolean): void {
    const parsed = parseCookieIdentity(value);
    let changed = false;
    if (parsed.memberId.length > 0) {
      this.memberId = parsed.memberId;
      changed = true;
    }
    if (parsed.passHash.length > 0) {
      this.passHash = parsed.passHash;
      changed = true;
    }
    if (parsed.igneous.length > 0) {
      this.igneous = parsed.igneous;
      changed = true;
    }
    if (showStatus) {
      this.statusText = changed ? 'Cookie fields detected' : 'No known Cookie fields detected';
    }
  }

  private validateCookieFields(): boolean {
    const id = this.memberId.trim();
    const hash = this.passHash.trim();
    if (id.length === 0) {
      this.statusText = 'ipb_member_id is empty';
      return false;
    }
    if (hash.length === 0) {
      this.statusText = 'ipb_pass_hash is empty';
      return false;
    }
    if (!checkIpbMemberId(id)) {
      this.statusText = 'ipb_member_id should contain digits only';
      return false;
    }
    if (!checkIpbPassHash(hash)) {
      this.statusText = 'ipb_pass_hash should be 32 lowercase letters or digits';
      return false;
    }
    return true;
  }

  private clearCookie(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.cookieInput = '';
      this.statusText = 'Cookie cleared in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.cookieInput = '';
      this.memberId = '';
      this.passHash = '';
      this.igneous = '';
      this.statusText = 'Cookie cleared';
    }).catch((error: Error) => {
      this.statusText = 'Cookie clear failed: ' + error.message;
    });
  }

  build() {
    Column() {
      if (this.mode === SessionMode.Web) {
        this.WebSignInPanel()
      } else if (this.mode === SessionMode.Cookie) {
        this.CookieSignInPanel()
      } else {
        this.PasswordSignInPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PasswordSignInPanel() {
    Stack() {
      Scroll() {
        Column() {
          SignInMark({ label: 'EH' })

          Column() {
          TextInput({ text: this.username, placeholder: uiText('Username') })
              .height(46)
              .width('100%')
              .onChange((value: string) => {
                this.username = value;
              })
            TextInput({ text: this.password, placeholder: uiText('Password') })
              .height(46)
              .width('100%')
              .margin({ top: 10 })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.password = value;
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 420 })
          .margin({ top: 8 })

          Text(uiStatusText(this.statusText))
            .fontSize(13)
            .fontColor('#0A6B45')
            .textAlign(TextAlign.Center)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 12 })

          Blank()
            .layoutWeight(1)

          Row() {
            Button(uiText('Register'))
              .type(ButtonType.Normal)
              .fontColor('#2F6F8F')
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
            Button(this.signingIn ? uiText('Signing in...') : uiText('Sign in'))
              .type(ButtonType.Normal)
              .fontColor('#2F6F8F')
              .fontWeight(FontWeight.Bold)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .enabled(!this.signingIn)
              .onClick(() => {
                this.signInWithPassword();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 520 })
          .margin({ top: 22 })

          Text(uiText('Sign in via WebView'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 8 })
            .onClick(() => {
              this.prepareWebSignIn();
              this.switchMode(SessionMode.Web);
            })
          Text(uiText('Sign in via Cookies'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 10 })
            .onClick(() => {
              this.switchMode(SessionMode.Cookie);
            })
          Text(uiText('Guest mode'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 10, bottom: 18 })
            .onClick(() => {
              this.onSignedIn();
            })
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .padding(20)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private CookieSignInPanel() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.switchMode(SessionMode.Password);
        })
        Text(uiText('Cookie Sign In'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#17202A')
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      SignInMark({ label: 'CK' })
        .margin({ top: 6 })

      Scroll() {
        Column() {
          Text(uiText('Use this when password login needs captcha, or when importing an ExHentai session.'))
            .fontSize(13)
            .fontColor('#475467')
            .lineHeight(20)
            .width('100%')
            .constraintSize({ maxWidth: 420 })

          TextInput({ text: this.memberId, placeholder: 'ipb_member_id' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 14 })
            .onChange((value: string) => {
              this.memberId = value;
            })
          TextInput({ text: this.passHash, placeholder: 'ipb_pass_hash' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.passHash = value;
            })
          TextInput({ text: this.igneous, placeholder: 'igneous' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.igneous = value;
            })
          TextArea({ text: this.cookieInput, placeholder: uiText('Full Cookie header') })
            .height(116)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .fontSize(13)
            .margin({ top: 12 })
            .onChange((value: string) => {
              this.cookieInput = value;
              this.syncCookieFieldsFromInput(value, true);
            })

          Text(uiStatusText(this.statusText))
            .fontSize(13)
            .fontColor('#0A6B45')
            .textAlign(TextAlign.Center)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 12 })
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Button(uiText('Clear'))
          .type(ButtonType.Normal)
          .fontColor('#2F6F8F')
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.clearCookie();
          })
        Button(uiText('OK'))
          .type(ButtonType.Normal)
          .fontColor('#2F6F8F')
          .fontWeight(FontWeight.Bold)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.saveCookie();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private WebSignInPanel() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.switchMode(SessionMode.Password);
        })
        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.White)

      Web({ src: this.webUrl, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageEnd((event: OnPageEndEvent) => {
          this.checkWebCookie(event.url);
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct SettingsScene {
  @State panel: SettingsPanel = SettingsPanel.Main;
  @State signedIn: boolean = ehCookieStore.hasCookies();
  @State statusText: string = '';
  @State themeName: string = 'Light';
  @State settingEntries: SettingEntry[] = defaultSettingEntries();
  @State optionPickerOpen: boolean = false;
  @State optionKey: string = '';
  @State optionTitle: string = '';
  @State optionSummary: string = '';
  @State optionValue: string = '';
  @State optionOptions: string[] = [];
  @State webViewUrl: string = '';
  @State webViewTitle: string = '';
  @State filterRules: FilterRule[] = [];
  @State filterNewText: string = '';
  @State filterNewMode: number = FILTER_MODE_TITLE;
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    activeBackHandler = () => this.handleSystemBack();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).then(() => {
        this.signedIn = ehCookieStore.hasCookies();
        this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
      ehSettingsStore.load(context).then(() => {
        this.settingEntries = ehSettingsStore.getEntries();
        this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
      }).catch((error: Error) => {
        this.statusText = 'Settings load failed: ' + error.message;
      });
    } else {
      this.signedIn = ehCookieStore.hasCookies();
      this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      this.settingEntries = ehSettingsStore.getEntries();
      this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    }
  }

  aboutToDisappear(): void {
    activeBackHandler = null;
  }

  private handleSystemBack(): boolean {
    if (this.optionPickerOpen) {
      this.optionPickerOpen = false;
      return true;
    }
    if (this.panel !== SettingsPanel.Main) {
      this.closePanel();
      return true;
    }
    return false;
  }

  private openPanel(panel: SettingsPanel): void {
    this.optionPickerOpen = false;
    this.panel = panel;
  }

  private closePanel(): void {
    this.optionPickerOpen = false;
    this.panel = SettingsPanel.Main;
    this.signedIn = ehCookieStore.hasCookies();
  }

  private signOut(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.signedIn = false;
      this.statusText = 'Signed out in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.signedIn = false;
      this.statusText = 'Signed out';
    }).catch((error: Error) => {
      this.statusText = 'Sign out failed: ' + error.message;
    });
  }

  private cycleTheme(): void {
    this.saveSettingValue('theme', nextOption(this.themeName, ['Light', 'Dark', 'Black']));
    this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    this.statusText = 'Theme preference saved: ' + this.themeName;
  }

  private saveSettingValue(key: string, value: string): void {
    if (key === 'proxy_port' && value.length > 0 && !isValidProxyPortText(value)) {
      this.statusText = 'Invalid proxy port: ' + value;
      return;
    }
    ehSettingsStore.setValue(key, value);
    this.settingEntries = ehSettingsStore.getEntries();
    this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    if (key === this.optionKey) {
      this.optionValue = value;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting in memory: ' + key + ' = ' + value +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved in memory: ' + key + ' = ' + value;
      return;
    }
    ehSettingsStore.save(context).then(() => {
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting: ' + key + ' = ' + value +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved: ' + key + ' = ' + value;
    }).catch((error: Error) => {
      this.statusText = 'Save failed: ' + error.message;
    });
  }

  private cycleSetting(row: SettingsRowItem): void {
    if (row.key === undefined) {
      this.statusText = row.title + ' is not available';
      return;
    }
    if (this.runSettingAction(row.key)) {
      return;
    }
    if (row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not migrated yet';
      return;
    }
    if (row.type === 'switch') {
      this.saveSettingValue(row.key, row.value === 'On' ? 'Off' : 'On');
      return;
    }
    this.openOptionPicker(row);
  }

  private openOptionPicker(row: SettingsRowItem): void {
    if (row.key === undefined || row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not available';
      return;
    }
    this.optionKey = row.key;
    this.optionTitle = row.title;
    this.optionSummary = row.summary;
    this.optionValue = settingEntryValue(this.settingEntries, row.key, row.value);
    this.optionOptions = cloneStringOptions(row.options);
    this.optionPickerOpen = true;
    this.statusText = '';
  }

  private closeOptionPicker(): void {
    this.optionPickerOpen = false;
    this.optionKey = '';
    this.optionTitle = '';
    this.optionSummary = '';
    this.optionValue = '';
    this.optionOptions = [];
  }

  private selectOptionValue(value: string): void {
    if (this.optionKey.length === 0) {
      this.statusText = 'No setting is selected';
      return;
    }
    this.saveSettingValue(this.optionKey, value);
    this.closeOptionPicker();
  }

  private runSettingAction(key: string): boolean {
    if (key === 'identity_cookie') {
      this.openPanel(SettingsPanel.Session);
      return true;
    }
    if (key === 'network_diagnostics') {
      this.runNetworkDiagnostics();
      return true;
    }
    if (key === 'restore_download_items') {
      this.restoreDownloadItems();
      return true;
    }
    if (key === 'clean_redundancy') {
      this.scanDownloadRedundancy();
      return true;
    }
    if (key === 'clear_download_path_cache') {
      this.refreshDownloadPathCache();
      return true;
    }
    if (key === 'clear_memory_cache') {
      this.clearMemoryCache();
      return true;
    }
    if (key === 'about_analytics') {
      this.statusText = 'Analytics is only recorded when enabled. The HarmonyOS port currently keeps this as a local preference.';
      return true;
    }
    if (key === 'declaration') {
      this.statusText = 'EhViewer_CN_SXJ HarmonyOS port keeps the original project notice and uses migrated local services where available.';
      return true;
    }
    if (key === 'author') {
      this.statusText = 'Original project: xiaojieonly/Ehviewer_CN_SXJ. HarmonyOS migration continues from the local workspace.';
      return true;
    }
    if (key === 'latest_release') {
      this.statusText = 'Latest release: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/releases';
      return true;
    }
    if (key === 'issue_help') {
      this.statusText = 'Issue help: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/issues';
      return true;
    }
    if (key === 'license') {
      this.statusText = 'License: GPL-compatible open-source project. Keep source disclosure for redistributed builds.';
      return true;
    }
    if (key === 'version') {
      this.statusText = 'Version: HarmonyOS port target 6.1.0 / API 6.1.1 (24), app version 1.3.1.';
      return true;
    }
    if (key === 'check_for_updates') {
      this.statusText = 'Update check uses the release page for now: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/releases';
      return true;
    }
    if (key === 'donate') {
      this.statusText = 'Donate entry is retained from the original app; payment integration is not migrated yet.';
      return true;
    }
    if (key === 'dump_logcat') {
      this.statusText = 'Android logcat export has no direct HarmonyOS equivalent yet. Crash/log persistence settings are available above.';
      return true;
    }
    if (key === 'u_config') {
      if (!this.signedIn) {
        this.statusText = 'UConfig requires a signed-in session';
        return true;
      }
      const isEx = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.webViewUrl = isEx ? 'https://exhentai.org/uconfig.php' : 'https://e-hentai.org/uconfig.php';
      this.webViewTitle = 'UConfig';
      this.openPanel(SettingsPanel.WebView);
      return true;
    }
    if (key === 'my_tags') {
      if (!this.signedIn) {
        this.statusText = 'My Tags requires a signed-in session';
        return true;
      }
      const isEx = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.webViewUrl = isEx ? 'https://exhentai.org/mytags' : 'https://e-hentai.org/mytags';
      this.webViewTitle = 'My Tags';
      this.openPanel(SettingsPanel.WebView);
      return true;
    }
    if (key === 'filter' || key === 'blacklist') {
      const context = getAbilityContext();
      if (context !== undefined) {
        ehFilterStore.load(context).then(() => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
        }).catch((error: Error) => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
          this.statusText = 'Filter load warning: ' + error.message;
        });
      } else {
        this.filterRules = ehFilterStore.getRules();
        this.openPanel(SettingsPanel.Filter);
      }
      return true;
    }
    if (key === 'pattern_protection') {
      this.runBiometricLock();
      return true;
    }
    if (key === 'export_data') {
      this.exportData();
      return true;
    }
    if (key === 'import_data') {
      this.importData();
      return true;
    }
    if (key === 'wifi_transfer') {
      this.statusText = settingMigrationMessage(key);
      return true;
    }
    return false;
  }

  private runBiometricLock(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Biometric lock requires an ability context';
      return;
    }
    const enabled = ehSettingsStore.getValue('pattern_protection', 'Off') === 'On';
    const next = enabled ? 'Off' : 'On';
    ehSettingsStore.setValue('pattern_protection', next);
    this.settingEntries = ehSettingsStore.getEntries();
    ehSettingsStore.save(context).catch((error: Error) => {
      this.statusText = 'Save failed: ' + error.message;
    });
    this.statusText = next === 'On'
      ? 'Biometric lock enabled: app will prompt for fingerprint/face on resume'
      : 'Biometric lock disabled';
  }

  private exportData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Export needs an ability context';
      return;
    }
    this.statusText = 'Preparing export...';
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_backup_' + stamp + '.json';

    Promise.all([
      ehSettingsStore.load(context),
      ehHistoryStore.load(context),
      ehDownloadStore.load(context),
      ehFilterStore.load(context)
    ]).then(() => {
      const bundle: EhBackupBundle = {
        version: 1,
        exportedAt: now.toISOString(),
        cookies: ehCookieStore.getCookieHeader(),
        settings: ehSettingsStore.getEntries(),
        history: ehHistoryStore.getItems(),
        downloadItems: ehDownloadStore.getItems(),
        downloadLabels: ehDownloadStore.getLabels(),
        filterRules: ehFilterStore.getRules()
      };
      const json = JSON.stringify(bundle, null, 2);

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(saveOptions).then((uris: string[]) => {
        if (uris.length === 0) {
          this.statusText = 'Export cancelled';
          return;
        }
        const uri = uris[0];
        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, json);
          fs.closeSync(file.fd);
          this.statusText = 'Export saved: ' + uri;
        } catch (error) {
          this.statusText = 'Export write failed: ' + String(error);
        }
      }).catch((error: Error) => {
        this.statusText = 'Export picker failed: ' + error.message;
      });
    }).catch((error: Error) => {
      this.statusText = 'Export load failed: ' + error.message;
    });
  }

  private importData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Import needs an ability context';
      return;
    }
    this.statusText = 'Select backup file to import...';

    const selectOptions = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(selectOptions).then((uris: string[]) => {
      if (uris.length === 0) {
        this.statusText = 'Import cancelled';
        return;
      }
      const uri = uris[0];
      try {
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const decoder = util.TextDecoder.create('utf-8');
        const json = decoder.decodeToString(new Uint8Array(buf));
        const bundle = JSON.parse(json) as EhBackupBundle;

        if (typeof bundle.version !== 'number') {
          this.statusText = 'Import failed: not a valid EhViewer backup file';
          return;
        }

        const saves: Promise<void>[] = [];

        if (typeof bundle.cookies === 'string' && bundle.cookies.length > 0) {
          ehCookieStore.setCookieHeader(bundle.cookies);
          saves.push(ehCookieStore.save(context));
          this.signedIn = ehCookieStore.hasCookies();
        }

        if (Array.isArray(bundle.settings)) {
          for (let i = 0; i < bundle.settings.length; i++) {
            const e = bundle.settings[i] as SettingEntry;
            if (typeof e.key === 'string' && typeof e.value === 'string') {
              ehSettingsStore.setValue(e.key, e.value);
            }
          }
          saves.push(ehSettingsStore.save(context));
          this.settingEntries = ehSettingsStore.getEntries();
          this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
        }

        if (Array.isArray(bundle.history)) {
          for (let i = 0; i < bundle.history.length; i++) {
            ehHistoryStore.addGallery(bundle.history[i] as GalleryInfo);
          }
          saves.push(ehHistoryStore.save(context));
        }

        if (Array.isArray(bundle.downloadLabels)) {
          for (let i = 0; i < bundle.downloadLabels.length; i++) {
            const lbl = bundle.downloadLabels[i] as DownloadLabel;
            if (typeof lbl.label === 'string') {
              ehDownloadStore.addLabel(lbl.label);
            }
          }
        }

        if (Array.isArray(bundle.downloadItems)) {
          for (let i = 0; i < bundle.downloadItems.length; i++) {
            const dl = bundle.downloadItems[i] as DownloadInfo;
            if (typeof dl.gid === 'number' && dl.gid > 0 && typeof dl.token === 'string') {
              ehDownloadStore.addGallery(dl as GalleryInfo, typeof dl.label === 'string' ? dl.label : '');
            }
          }
          saves.push(ehDownloadStore.save(context));
        }

        if (Array.isArray(bundle.filterRules)) {
          for (let i = 0; i < bundle.filterRules.length; i++) {
            const r = bundle.filterRules[i] as FilterRule;
            if (typeof r.text === 'string' && typeof r.mode === 'number') {
              ehFilterStore.addRule(r.mode, r.text);
            }
          }
          saves.push(ehFilterStore.save(context));
          this.filterRules = ehFilterStore.getRules();
        }

        Promise.all(saves).then(() => {
          this.statusText = 'Import complete';
        }).catch((error: Error) => {
          this.statusText = 'Import save failed: ' + error.message;
        });

      } catch (error) {
        this.statusText = 'Import failed: ' + String(error);
      }
    }).catch((error: Error) => {
      this.statusText = 'Import picker failed: ' + error.message;
    });
  }

  private restoreDownloadItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore download items needs an ability context';
      return;
    }
    this.statusText = 'Scanning downloaded folders...';
    ehDownloadStore.load(context).then(() => {
      const restored: RestoredDownloadGallery[] = ehDownloadFileStore.restoreDownloadedGalleries(context);
      let added = 0;
      let updated = 0;
      let totalBytes = 0;
      for (let i = 0; i < restored.length; i++) {
        const item = restored[i];
        const existed = ehDownloadStore.contains(item.gallery.gid);
        if (ehDownloadStore.addGallery(item.gallery, '') !== null) {
          const total = Math.max(item.total, item.finished);
          ehDownloadStore.setProgress(item.gallery.gid, item.finished, total, item.finished);
          ehDownloadStore.setStorage(item.gallery.gid, item.directory, item.fileSize);
          ehDownloadStore.setState(item.gallery.gid,
            total > 0 && item.finished >= total ? DownloadState.Finish : DownloadState.None);
          totalBytes += item.fileSize;
          if (existed) {
            updated++;
          } else {
            added++;
          }
        }
      }
      return ehDownloadStore.save(context).then(() => {
        this.statusText = 'Restored downloads: ' + added.toString() + ' added, ' + updated.toString() +
          ' updated, ' + downloadSizeText(totalBytes) + '.';
      });
    }).catch((error: Error) => {
      this.statusText = 'Restore downloads failed: ' + error.message;
    });
  }

  private scanDownloadRedundancy(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Clean redundancy needs an ability context';
      return;
    }
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      const keepGids: number[] = [];
      for (let i = 0; i < items.length; i++) {
        keepGids.push(items[i].gid);
      }
      const result: DownloadDirectoryScanResult = ehDownloadFileStore.scanRedundantDirectories(context, keepGids);
      this.statusText = 'Redundancy scan: ' + result.directories.toString() + ' folders, ' +
        result.files.toString() + ' images, ' + downloadSizeText(result.bytes) +
        '. Restore downloads before deleting any folder manually.';
    }).catch((error: Error) => {
      this.statusText = 'Redundancy scan failed: ' + error.message;
    });
  }

  private refreshDownloadPathCache(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download path cache needs an ability context';
      return;
    }
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      let updated = 0;
      let totalBytes = 0;
      for (let i = 0; i < items.length; i++) {
        const size = ehDownloadFileStore.directorySize(context, items[i]);
        if (size > 0) {
          ehDownloadStore.setStorage(items[i].gid, ehDownloadFileStore.galleryDirectory(context, items[i]), size);
          totalBytes += size;
          updated++;
        }
      }
      return ehDownloadStore.save(context).then(() => {
        this.statusText = 'Download path cache refreshed: ' + updated.toString() + ' items, ' +
          downloadSizeText(totalBytes) + '.';
      });
    }).catch((error: Error) => {
      this.statusText = 'Refresh download path cache failed: ' + error.message;
    });
  }

  private clearMemoryCache(): void {
    const pageCount = galleryPageCache.clear();
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Cleared page cache: ' + pageCount.toString() + ' entries.';
      return;
    }
    const imageResult: CacheClearResult = readerImageCache.clear(context);
    this.statusText = 'Cleared cache: ' + pageCount.toString() + ' pages, ' +
      imageResult.files.toString() + ' images, ' + downloadSizeText(imageResult.bytes) + '.';
  }

  private runNetworkDiagnostics(): void {
    this.statusText = 'Running network diagnostics...';
    this.client.runNetworkDiagnostics().then((results: NetworkDiagnosticResult[]) => {
      this.statusText = formatNetworkDiagnostics(results);
    }).catch((error: Error) => {
      this.statusText = 'Network diagnostics failed: ' + error.message;
    });
  }

  private addFilterRule(): void {
    const text = this.filterNewText.trim();
    if (text.length === 0) {
      this.statusText = 'Enter a filter text first';
      return;
    }
    const added = ehFilterStore.addRule(this.filterNewMode, text);
    if (!added) {
      this.statusText = 'Rule already exists: ' + text;
      return;
    }
    this.filterRules = ehFilterStore.getRules();
    this.filterNewText = '';
    this.statusText = 'Filter rule added: ' + text;
    this.saveFilterRules();
  }

  private removeFilterRule(id: number): void {
    ehFilterStore.removeRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.statusText = 'Filter rule removed';
    this.saveFilterRules();
  }

  private toggleFilterRule(id: number): void {
    ehFilterStore.toggleRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.saveFilterRules();
  }

  private saveFilterRules(): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehFilterStore.save(context).catch((error: Error) => {
        this.statusText = 'Filter save failed: ' + error.message;
      });
    }
  }


  build() {
    if (this.optionPickerOpen) {
      SettingsOptionPanel({
        title: this.optionTitle,
        summary: this.optionSummary,
        value: this.optionValue,
        options: this.optionOptions,
        onBack: () => {
          this.closeOptionPicker();
        },
        onSelect: (value: string) => {
          this.selectOptionValue(value);
        }
      })
    } else if (this.panel === SettingsPanel.Filter) {
      FilterPanel({
        rules: this.filterRules,
        newText: this.filterNewText,
        newMode: this.filterNewMode,
        statusText: this.statusText,
        onBack: () => {
          this.closePanel();
        },
        onNewTextChange: (text: string) => {
          this.filterNewText = text;
        },
        onNewModeChange: (mode: number) => {
          this.filterNewMode = mode;
        },
        onAdd: () => {
          this.addFilterRule();
        },
        onRemove: (id: number) => {
          this.removeFilterRule(id);
        },
        onToggle: (id: number) => {
          this.toggleFilterRule(id);
        }
      })
    } else if (this.panel === SettingsPanel.WebView) {
      Column() {
        SettingsSubToolbar({
          title: uiText(this.webViewTitle),
          onBack: () => {
            this.closePanel();
          }
        })
        Web({ src: this.webViewUrl, controller: this.webViewController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Session) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Sign in'),
          onBack: () => {
            this.closePanel();
          }
        })
        SessionScene({
          onSignedIn: () => {
            this.signedIn = ehCookieStore.hasCookies();
            this.statusText = this.signedIn ? 'Signed in' : 'Guest mode';
            this.closePanel();
            this.onSignedIn();
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Migration) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Migration'),
          onBack: () => {
            this.closePanel();
          }
        })
        MigrationScene()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Main) {
      SettingsHomePanel({
        signedIn: this.signedIn,
        statusText: this.statusText,
        onMenu: this.onMenu,
        onOpen: (panel: SettingsPanel) => {
          this.openPanel(panel);
        }
      })
    } else {
      SettingsDetailPanel({
        panel: this.panel,
        signedIn: this.signedIn,
        statusText: this.statusText,
        themeName: this.themeName,
        settingEntries: this.settingEntries,
        onBack: () => {
          this.closePanel();
        },
        onOpenSession: () => {
          this.openPanel(SettingsPanel.Session);
        },
        onOpenMigration: () => {
          this.openPanel(SettingsPanel.Migration);
        },
        onSignOut: () => {
          this.signOut();
        },
        onCycleTheme: () => {
          this.cycleTheme();
        },
        onCycleSetting: (row: SettingsRowItem) => {
          this.cycleSetting(row);
        },
        onSetSetting: (key: string, value: string) => {
          this.saveSettingValue(key, value);
        }
      })
    }
  }
}

@Component
struct SettingsHomePanel {
  @Prop signedIn: boolean = false;
  @Prop statusText: string = '';
  onMenu: () => void = () => {};
  onOpen: (panel: SettingsPanel) => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .onClick(() => {
          this.onMenu();
        })
        Column() {
          Text(uiText('Settings'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.signedIn ? uiText('Signed in') : uiText('Guest mode'))
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Text(this.signedIn ? 'EH' : '?')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2F6F8F')
          .textAlign(TextAlign.Center)
          .width(36)
          .height(36)
          .backgroundColor(Color.White)
          .borderRadius(18)
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#2F6F8F')

      if (this.statusText.length > 0) {
        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(11)
            .fontColor('#40566F')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(28)
        .padding({ left: 14, right: 14 })
        .backgroundColor('#EAF3F8')
      }

      List({ space: 8 }) {
        ForEach(SETTINGS_HEADERS, (item: SettingsHeaderItem) => {
          ListItem() {
            SettingsHeaderRow({
              item: item,
              onTap: () => {
                this.onOpen(item.panel);
              }
            })
          }
        }, (item: SettingsHeaderItem) => item.panel)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct SettingsHeaderRow {
  item: SettingsHeaderItem = { panel: SettingsPanel.Eh, title: '', icon: '', summary: '' };
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .borderRadius(18)
        .padding({ top: 9 })
      Column() {
        Text(uiText(this.item.title))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(uiText(this.item.summary))
          .fontSize(12)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text('>')
        .fontSize(16)
        .fontColor('#98A2B3')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
struct SettingsDetailPanel {
  panel: SettingsPanel = SettingsPanel.Eh;
  @Prop signedIn: boolean = false;
  @Prop statusText: string = '';
  @Prop themeName: string = 'Light';
  @Prop settingEntries: SettingEntry[] = [];
  onBack: () => void = () => {};
  onOpenSession: () => void = () => {};
  onOpenMigration: () => void = () => {};
  onSignOut: () => void = () => {};
  onCycleTheme: () => void = () => {};
  onCycleSetting: (row: SettingsRowItem) => void = () => {};
  onSetSetting: (key: string, value: string) => void = () => {};

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText(settingsPanelTitle(this.panel)),
        onBack: this.onBack
      })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor('#0A6B45')
          .width('100%')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('#F0FBF6')
      }

      List({ space: 8 }) {
        if (this.panel === SettingsPanel.Eh) {
          ListItem() {
            SettingsActionRow({
              title: this.signedIn ? uiText('Account session') : uiText('Sign in'),
              summary: this.signedIn ? uiText('Cookie session is available. Open to replace or inspect cookies.') :
                uiText('Open password, WebView or Cookie sign-in. This matches the original startup sign-in flow.'),
              value: this.signedIn ? uiText('Signed in') : uiText('Tourist'),
              onTap: this.onOpenSession
            })
          }
          ListItem() {
            SettingsActionRow({
              title: uiText('Sign out'),
              summary: uiText('Clear the persisted identity cookies'),
              value: this.signedIn ? uiText('Available') : uiText('No session'),
              isEnabled: this.signedIn,
              onTap: this.onSignOut
            })
          }
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
          ListItem() {
            SettingsActionRow({
              title: uiText('Theme'),
              summary: uiText('Original app cycles Light, Dark and Black from drawer/footer and Settings'),
              value: uiValue(this.themeName),
              onTap: this.onCycleTheme
            })
          }
        } else if (this.panel === SettingsPanel.About) {
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
          ListItem() {
            SettingsActionRow({
              title: uiText('Migration status'),
              summary: uiText('Open the HarmonyOS port checklist'),
              value: uiText('Open'),
              onTap: this.onOpenMigration
            })
          }
        } else {
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        }

      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct SettingsOptionPanel {
  title: string = '';
  summary: string = '';
  value: string = '';
  options: string[] = [];
  onBack: () => void = () => {};
  onSelect: (value: string) => void = () => {};

  build() {
    Column() {
      SettingsSubToolbar({
        title: this.title,
        onBack: this.onBack
      })

      if (this.summary.length > 0) {
        Text(uiText(this.summary))
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 10 })
          .backgroundColor(Color.White)
      }

      List({ space: 8 }) {
        ForEach(this.options, (option: string) => {
          ListItem() {
            Row() {
              Text(uiValue(option))
                .fontSize(15)
                .fontWeight(option === this.value ? FontWeight.Medium : FontWeight.Regular)
                .fontColor('#17202A')
                .layoutWeight(1)
              if (option === this.value) {
                Text(uiText('Selected'))
                  .fontSize(12)
                  .fontColor('#2F6F8F')
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Color.White)
            .borderRadius(6)
            .onClick(() => {
              this.onSelect(option);
            })
          }
        }, (option: string) => option)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct SettingsSubToolbar {
  title: string = '';
  onBack: () => void = () => {};

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(38)
      .height(38)
      .backgroundColor('rgba(255,255,255,0.15)')
      .onClick(() => {
        this.onBack();
      })
      Text(uiText(this.title))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#2F6F8F')
  }
}

@Component
struct SettingsActionRow {
  title: string = '';
  summary: string = '';
  value: string = '';
  isEnabled: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isEnabled ? '#17202A' : '#98A2B3')
        Text(this.summary)
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.value)
        .fontSize(12)
        .fontColor(this.isEnabled ? '#2F6F8F' : '#98A2B3')
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

@Component
struct SettingsStaticRow {
  row: SettingsRowItem = { title: '', summary: '', value: '', type: '' };
  onTap: () => void = () => {};
  onTextChange: (key: string, value: string) => void = () => {};
  onSwitchChange: (key: string, isOn: boolean) => void = () => {};
  onOptionSelect: (key: string, value: string) => void = () => {};

  build() {
    Row() {
      Column() {
        Text(uiText(this.row.title))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(uiText(this.row.summary))
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.row.type === 'input') {
        TextInput({ text: this.row.value, placeholder: this.row.summary })
          .width(150)
          .height(38)
          .fontSize(13)
          .margin({ left: 12 })
          .onChange((value: string) => {
            if (this.row.key !== undefined) {
              this.onTextChange(this.row.key, value.trim());
            }
          })
      } else if (this.row.type === 'switch') {
        Row() {
          Text(this.row.value === 'On' ? uiText('On') : uiText('Off'))
            .fontSize(12)
            .fontColor(this.row.value === 'On' ? '#2F6F8F' : '#98A2B3')
            .margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: this.row.value === 'On' })
            .selectedColor('#2F6F8F')
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              if (this.row.key !== undefined) {
                this.onSwitchChange(this.row.key, isOn);
              }
            })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 12 })
      } else if (this.row.type === 'list' && this.row.options !== undefined && this.row.options.length > 0) {
        Select(buildSelectOptions(this.row.options))
          .selected(optionIndex(this.row.options, this.row.value))
          .value(uiValue(this.row.value))
          .font({ size: 13 })
          .fontColor('#2F6F8F')
          .selectedOptionBgColor('#EDF7FA')
          .selectedOptionFontColor('#2F6F8F')
          .optionBgColor(Color.White)
          .optionFont({ size: 13 })
          .margin({ left: 8 })
          .onSelect((index: number) => {
            if (this.row.key !== undefined && this.row.options !== undefined) {
              this.onOptionSelect(this.row.key, this.row.options[index]);
            }
          })
      } else {
        Button(settingsRowActionText(this.row))
          .height(34)
          .fontSize(12)
          .fontColor('#40566F')
          .backgroundColor('#F2F4F7')
          .margin({ left: 12 })
          .onClick(() => {
            this.onTap();
          })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      if (this.row.type !== 'input' && this.row.type !== 'switch' && this.row.type !== 'list') {
        this.onTap();
      }
    })
  }
}

function settingsRowActionText(row: SettingsRowItem): string {
  if (row.value.length > 0) {
    return uiValue(row.value);
  }
  return uiText('Open');
}

function buildSelectOptions(options: string[]): SelectOption[] {
  const result: SelectOption[] = [];
  for (let i = 0; i < options.length; i++) {
    result.push({ value: uiValue(options[i]) });
  }
  return result;
}

function optionIndex(options: string[], value: string): number {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === value) {
      return i;
    }
  }
  return 0;
}

function settingsRowRenderKey(row: SettingsRowItem): string {
  return row.title + ':' + row.value + ':' + row.type;
}

function isNetworkSettingKey(key: string): boolean {
  return key === 'proxy' || key === 'proxy_host' || key === 'proxy_port' || key === 'built_in_hosts' ||
    key === 'built_ex_hosts' || key === 'dns_over_https' || key === 'domain_fronting';
}

@Component
struct SignInMark {
  label: string = '';

  build() {
    Text(this.label)
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(72)
      .height(72)
      .backgroundColor('#2F6F8F')
      .borderRadius(18)
      .padding({ top: 18 })
  }
}

function collectWebCookies(currentUrl: string): string {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeader(currentUrl, names, values);
  absorbCookieHeader(EhUrl.HOST_E, names, values);
  absorbCookieHeader(EhUrl.HOST_EX, names, values);
  absorbCookieHeader(EhUrl.FORUM_ORIGIN, names, values);
  absorbCookieHeader(EhUrl.URL_SIGN_IN, names, values);

  const parts: string[] = [];
  for (let i = 0; i < names.length; i++) {
    parts.push(names[i] + '=' + values[i]);
  }
  return parts.join('; ');
}

interface CookieIdentity {
  memberId: string;
  passHash: string;
  igneous: string;
}

function parseCookieIdentity(text: string): CookieIdentity {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeaderText(text, names, values);
  return {
    memberId: findCookieValue('ipb_member_id', names, values),
    passHash: findCookieValue('ipb_pass_hash', names, values),
    igneous: findCookieValue('igneous', names, values)
  };
}

function absorbCookieHeaderText(text: string, names: string[], values: string[]): void {
  if (text.trim().length === 0) {
    return;
  }

  const rows = text.replace(/\r/g, '\n').split('\n');
  for (let i = 0; i < rows.length; i++) {
    absorbCookieRow(rows[i], names, values);
  }
}

function absorbCookieRow(row: string, names: string[], values: string[]): void {
  const trimmed = row.trim();
  if (trimmed.length === 0) {
    return;
  }

  const colon = trimmed.indexOf(':');
  if (colon > 0) {
    const key = trimmed.substring(0, colon).trim();
    const value = trimmed.substring(colon + 1).trim();
    if (isKnownCookieName(key) && value.length > 0) {
      upsertCookiePair(key, value, names, values);
      return;
    }
  }

  const normalized = trimmed.startsWith('Cookie:') ? trimmed.substring(7).trim() : trimmed;
  const pieces = normalized.split(';');
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i].trim();
    const eq = piece.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key = piece.substring(0, eq).trim();
    const value = piece.substring(eq + 1).trim();
    if (key.length === 0 || value.length === 0 || isCookieAttribute(key)) {
      continue;
    }
    upsertCookiePair(key, value, names, values);
  }
}

function findCookieValue(name: string, names: string[], values: string[]): string {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      return values[i];
    }
  }
  return '';
}

function absorbCookieHeader(url: string, names: string[], values: string[]): void {
  if (url.length === 0) {
    return;
  }

  let header = '';
  try {
    header = webview.WebCookieManager.fetchCookieSync(url);
  } catch (error) {
    header = '';
  }
  if (header.length === 0) {
    return;
  }

  const pairs = header.split(';');
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i].trim();
    const index = pair.indexOf('=');
    if (index <= 0) {
      continue;
    }
    upsertCookiePair(pair.substring(0, index), pair.substring(index + 1), names, values);
  }
}

function upsertCookiePair(name: string, value: string, names: string[], values: string[]): void {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      values[i] = value;
      return;
    }
  }
  names.push(name);
  values.push(value);
}

function hasLoginCookie(cookieHeader: string): boolean {
  return cookieHeader.indexOf('ipb_member_id=') >= 0 && cookieHeader.indexOf('ipb_pass_hash=') >= 0;
}

function isKnownCookieName(name: string): boolean {
  return name === 'ipb_member_id' || name === 'ipb_pass_hash' || name === 'igneous' ||
    name === 'cf_clearance' || name === 'sk' || name === 'yay' || name === 'sl';
}

function isCookieAttribute(name: string): boolean {
  const lower = name.toLowerCase();
  return lower === 'domain' || lower === 'path' || lower === 'expires' || lower === 'max-age' ||
    lower === 'secure' || lower === 'httponly' || lower === 'samesite';
}

function checkIpbMemberId(id: string): boolean {
  if (id.length === 0) {
    return false;
  }
  for (let i = 0; i < id.length; i++) {
    const code = id.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function checkIpbPassHash(hash: string): boolean {
  if (hash.length !== 32) {
    return false;
  }
  for (let i = 0; i < hash.length; i++) {
    const code = hash.charCodeAt(i);
    const digit = code >= 48 && code <= 57;
    const lower = code >= 97 && code <= 122;
    if (!digit && !lower) {
      return false;
    }
  }
  return true;
}

@Component
struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State visibleItems: DownloadInfo[] = [];
  @State labels: DownloadLabel[] = [];
  @State query: string = '';
  @State statusFilter: string = 'All';
  @State labelFilter: string = 'All';
  @State sortMode: string = 'Default';
  @State newLabel: string = '';
  @State statusText: string = 'Download queue is ready';
  @State isProcessing: boolean = false;

  aboutToAppear(): void {
    this.loadDownloads();
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
      this.applyFilters();
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
      this.statusText = this.items.length.toString() + ' download items';
      this.applyFilters();
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
      this.applyFilters();
    });
  }

  private persistDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehDownloadStore.save(context).catch((error: Error) => {
      this.statusText = 'Download save failed: ' + error.message;
    });
  }

  private applyFilters(): void {
    this.visibleItems = filterDownloadItems(this.items, this.query, this.statusFilter, this.labelFilter, this.sortMode);
  }

  private startAll(): void {
    this.shouldStop = false;
    ehDownloadStore.startAll();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Queued idle and failed downloads';
    this.applyFilters();
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    ehDownloadStore.stopAll();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Stopped waiting downloads';
    this.applyFilters();
    this.persistDownloads();
  }

  private async runDownloadQueue(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }

    this.isProcessing = true;
    try {
      const workerCount = downloadThreadLimit();
      this.statusText = 'Download workers: ' + workerCount.toString();
      while (!this.shouldStop) {
        const queue = ehDownloadStore.getItems();
        const batch: DownloadInfo[] = [];
        for (let i = 0; i < queue.length && batch.length < workerCount; i++) {
          if (queue[i].state === DownloadState.Wait) {
            batch.push(queue[i]);
          }
        }
        if (batch.length === 0) {
          break;
        }

        const tasks: Promise<void>[] = [];
        for (let i = 0; i < batch.length; i++) {
          tasks.push(this.downloadOne(context, batch[i]));
        }
        await Promise.all(tasks);
      }
    } finally {
      this.isProcessing = false;
      this.items = ehDownloadStore.getItems();
      this.applyFilters();
      this.persistDownloads();
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Downloading: ' + item.title;
    this.applyFilters();
    this.persistDownloads();

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(), EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      ehDownloadStore.updateGallery(detailResult.detail);
      const total = detailResult.detail.previewSet.length > 0 ? detailResult.detail.previewSet.length : detailResult.detail.pages;
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detailResult.detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);
      this.items = ehDownloadStore.getItems();
      this.applyFilters();

      let finished = 0;
      let fileSize = ehDownloadFileStore.directorySize(context, detailResult.detail);
      for (let i = 0; i < detailResult.detail.previewSet.length; i++) {
        if (ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          finished++;
        }
      }
      if (finished > 0) {
        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.items = ehDownloadStore.getItems();
        this.statusText = 'Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.applyFilters();
        this.persistDownloads();
      }

      const pageIndexes = downloadPageIndexes(detailResult.detail.previewSet.length);
      for (let orderIndex = 0; orderIndex < pageIndexes.length; orderIndex++) {
        const i = pageIndexes[orderIndex];
        if (this.shouldStop) {
          ehDownloadStore.setState(item.gid, DownloadState.None);
          this.statusText = 'Stopped: ' + item.title;
          return;
        }

        const preview = detailResult.detail.previewSet[i];
        if (preview.pageUrl.length === 0) {
          continue;
        }

        if (ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          continue;
        }

        const pageResult = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(detailResult.url, detailResult.detail.previewSet, i, currentGallerySite()));
        if (!pageResult.ok || pageResult.page === null) {
          throw new Error(pageResult.message);
        }

        const imageUrl = downloadImageUrlForPage(pageResult.page);
        if (imageUrl.length === 0) {
          throw new Error('Image URL missing');
        }

        const cachedPath = await readerImageCache.ensureCached(context, imageUrl, pageResult.page.pageUrl, false);
        const savedPath = ehDownloadFileStore.savePageImage(context, detailResult.detail, pageResult.page, i, cachedPath);
        fileSize += ehDownloadFileStore.statFileSize(savedPath);
        finished++;
        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.items = ehDownloadStore.getItems();
        this.statusText = 'Downloaded ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.applyFilters();
        this.persistDownloads();
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
      this.statusText = 'Download finished: ' + item.title;
      this.items = ehDownloadStore.getItems();
      this.applyFilters();
      this.persistDownloads();
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      this.items = ehDownloadStore.getItems();
      this.statusText = 'Download failed: ' + String(error);
      this.applyFilters();
      this.persistDownloads();
    }
  }

  private clearFinished(): void {
    ehDownloadStore.clearFinished();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Cleared finished downloads';
    this.applyFilters();
    this.persistDownloads();
  }

  private addLabel(): void {
    if (ehDownloadStore.addLabel(this.newLabel)) {
      this.labels = ehDownloadStore.getLabels();
      this.statusText = 'Added label: ' + this.newLabel.trim();
      this.newLabel = '';
      this.applyFilters();
      this.persistDownloads();
    } else {
      this.statusText = 'Label is empty or already exists';
    }
  }

  private removeSelectedLabel(): void {
    if (this.labelFilter === 'All' || this.labelFilter === 'Default') {
      this.statusText = 'Select a custom label before deleting';
      return;
    }
    ehDownloadStore.removeLabel(this.labelFilter);
    this.labels = ehDownloadStore.getLabels();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Deleted label: ' + this.labelFilter;
    this.labelFilter = 'All';
    this.applyFilters();
    this.persistDownloads();
  }

  private removeItem(item: DownloadInfo): void {
    ehDownloadStore.removeGallery(item.gid);
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Removed: ' + item.title;
    this.applyFilters();
    this.persistDownloads();
  }

  private cycleItemState(item: DownloadInfo): void {
    ehDownloadStore.setState(item.gid, nextDownloadState(item.state));
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Updated state: ' + item.title;
    this.applyFilters();
    this.persistDownloads();
  }

  private cycleItemLabel(item: DownloadInfo): void {
    const label = nextDownloadLabel(item.label, this.labels);
    ehDownloadStore.setLabel(item.gid, label);
    this.items = ehDownloadStore.getItems();
    this.statusText = label.length === 0 ? 'Moved to default label: ' + item.title : 'Moved to label ' + label + ': ' + item.title;
    this.applyFilters();
    this.persistDownloads();
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .onClick(() => {
          this.onMenu();
        })
        TextInput({ text: this.query, placeholder: uiText('Search downloads') })
          .height(38)
          .layoutWeight(1)
          .backgroundColor(Color.White)
          .borderRadius(19)
          .placeholderColor('rgba(47,111,143,0.5)')
          .fontColor('#17202A')
          .caretColor('#2F6F8F')
          .padding({ left: 16, right: 16 })
          .margin({ left: 10 })
          .onChange((value: string) => {
            this.query = value;
            this.applyFilters();
          })
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .margin({ left: 10 })
        .onClick(() => {
          this.loadDownloads();
        })
      }
      .width('100%')
      .height(62)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#2F6F8F')

      Column() {
        Row() {
          Button(uiText('Status') + ': ' + uiValue(this.statusFilter))
            .height(30)
            .fontSize(12)
            .onClick(() => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
              this.applyFilters();
            })
          Button(uiText('Label') + ': ' + uiValue(this.labelFilter))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.labelFilter = nextDownloadLabelFilter(this.labelFilter, this.labels);
              this.applyFilters();
            })
          Button(uiText('Sort') + ': ' + uiValue(this.sortMode))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.sortMode = nextDownloadSortMode(this.sortMode);
              this.applyFilters();
            })
          Blank()
          Text(this.visibleItems.length.toString() + '/' + this.items.length.toString())
            .fontSize(12)
            .fontColor('#667085')
        }
        .width('100%')

        Row() {
          TextInput({ text: this.newLabel, placeholder: uiText('New label') })
            .height(34)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.newLabel = value;
            })
          Button(uiText('Add'))
            .height(34)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.addLabel();
            })
          Button(uiText('Delete'))
            .height(34)
            .fontSize(12)
            .margin({ left: 8 })
            .enabled(this.labelFilter !== 'All' && this.labelFilter !== 'Default')
            .onClick(() => {
              this.removeSelectedLabel();
            })
        }
        .width('100%')
        .margin({ top: 6 })

        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(11)
            .fontColor('#40566F')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(uiStatusText(downloadQueueSummary(this.items)))
            .fontSize(11)
            .fontColor('#667085')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(Color.White)
      .margin({ left: 12, right: 12, top: 12, bottom: 8 })

      if (this.visibleItems.length === 0) {
        Column() {
          Text(uiText('Downloads'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
          Text(this.items.length === 0 ? uiText('Download items will be shown here') : uiText('No items match the current filter'))
            .fontSize(14)
            .fontColor('#667085')
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.visibleItems, (item: DownloadInfo) => {
            ListItem() {
              DownloadRow({
                item: item,
                onState: () => {
                  this.cycleItemState(item);
                },
                onLabel: () => {
                  this.cycleItemLabel(item);
                },
                onRemove: () => {
                  this.removeItem(item);
                }
              })
            }
          }, (item: DownloadInfo) => item.gid.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, bottom: 8 })
      }

      Row() {
        Button(uiText('Start all'))
          .height(42)
          .layoutWeight(1)
          .onClick(() => {
            this.startAll();
          })
        Button(uiText('Stop all'))
          .height(42)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.stopAll();
          })
        Button(uiText('Clear done'))
          .height(42)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.clearFinished();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct DownloadRow {
  item: DownloadInfo = createEmptyDownloadInfo();
  onState: () => void = () => {};
  onLabel: () => void = () => {};
  onRemove: () => void = () => {};

  build() {
    Row() {
      GalleryThumb({
        url: this.item.thumb === undefined ? '' : this.item.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: galleryThumbHeight()
      })

      Column() {
        Row() {
          Text(galleryDisplayTitle(this.item))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#17202A')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(uiValue(downloadStateLabel(this.item.state)))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(downloadStateColor(this.item.state))
            .borderRadius(3)
        }
        .width('100%')

        Row() {
          CategoryBadge({ category: this.item.category })
          if (showGalleryPages()) {
            Text(this.item.pages.toString() + 'p')
              .fontSize(12)
              .fontColor('#667085')
              .margin({ left: 8 })
          }
          Text(this.item.label.length === 0 ? uiText('Default') : this.item.label)
            .fontSize(12)
            .fontColor('#667085')
            .margin({ left: 8 })
          Blank()
          Text(downloadProgressText(this.item))
            .fontSize(12)
            .fontColor('#667085')
        }
        .width('100%')
        .margin({ top: 8 })

        if (this.item.archiveUri.length > 0 || this.item.fileSize > 0) {
          Row() {
            Text(downloadSizeText(this.item.fileSize))
              .fontSize(11)
              .fontColor('#667085')
            Text(this.item.archiveUri)
              .fontSize(11)
              .fontColor('#98A2B3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ top: 6 })
        }

        Row() {
          Text(this.item.uploader === undefined || this.item.uploader.length === 0 ? uiText('unknown uploader') : this.item.uploader)
            .fontSize(12)
            .fontColor('#98A2B3')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button(uiText('State'))
            .height(30)
            .onClick(() => {
              this.onState();
            })
          Button(uiText('Label'))
            .height(30)
            .margin({ left: 6 })
            .onClick(() => {
              this.onLabel();
            })
          Button(uiText('Remove'))
            .height(30)
            .margin({ left: 6 })
            .onClick(() => {
              this.onRemove();
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .height(galleryRowHeight())
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
struct FilterPanel {
  rules: FilterRule[] = [];
  newText: string = '';
  newMode: number = FILTER_MODE_TITLE;
  statusText: string = '';
  onBack: () => void = () => {};
  onNewTextChange: (text: string) => void = () => {};
  onNewModeChange: (mode: number) => void = () => {};
  onAdd: () => void = () => {};
  onRemove: (id: number) => void = () => {};
  onToggle: (id: number) => void = () => {};

  private filterModeName(mode: number): string {
    if (mode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (mode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return uiText('Tag:Namespace');
    }
    return uiText('Title');
  }

  private cycleMode(): void {
    const next = (this.newMode + 1) % 4;
    this.onNewModeChange(next);
  }

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText('Filter rules'),
        onBack: this.onBack
      })

      Column() {
        Row() {
          TextInput({ text: this.newText, placeholder: uiText('Filter text') })
            .layoutWeight(1)
            .height(40)
            .onChange((value: string) => {
              this.onNewTextChange(value);
            })
          Button(this.filterModeName(this.newMode))
            .height(40)
            .margin({ left: 8 })
            .onClick(() => {
              this.cycleMode();
            })
          Button(uiText('Add'))
            .height(40)
            .margin({ left: 8 })
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.onAdd();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

        if (this.statusText.length > 0) {
          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor('#667085')
            .padding({ left: 16, right: 16, bottom: 8 })
            .width('100%')
        }

        Text(uiText('Mode: tap to cycle — Title / Uploader / Tag / Tag:Namespace'))
          .fontSize(11)
          .fontColor('#95A1B0')
          .padding({ left: 16, right: 16, bottom: 10 })
          .width('100%')
      }
      .backgroundColor(Color.White)

      if (this.rules.length === 0) {
        PlaceholderScene({
          title: 'No filters',
          detail: 'Add a filter rule above to hide matching galleries from lists.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.rules, (rule: FilterRule) => {
            ListItem() {
              Row() {
                Column() {
                  Text(rule.text)
                    .fontSize(14)
                    .fontColor(rule.enabled ? '#17202A' : '#95A1B0')
                    .fontWeight(rule.enabled ? FontWeight.Medium : FontWeight.Normal)
                  Text(this.filterModeName(rule.mode))
                    .fontSize(11)
                    .fontColor('#667085')
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(rule.enabled ? uiText('On') : uiText('Off'))
                  .height(30)
                  .fontSize(12)
                  .fontColor(rule.enabled ? '#0A6B45' : '#95A1B0')
                  .backgroundColor(rule.enabled ? '#EDFAF3' : '#F5F5F5')
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.onToggle(rule.id);
                  })
                Button(uiText('Remove'))
                  .height(30)
                  .fontSize(12)
                  .fontColor('#C33A2C')
                  .backgroundColor('#FDF0EE')
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.onRemove(rule.id);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 12, bottom: 12 })
              .backgroundColor(Color.White)
            }
          }, (rule: FilterRule) => rule.id.toString())
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

@Component
struct PlaceholderScene {
  title: string = '';
  detail: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17202A')
      Text(this.detail)
        .fontSize(14)
        .fontColor('#667085')
        .lineHeight(22)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}

@Component
struct MigrationScene {
  build() {
    List({ space: 10 }) {
      ForEach(migrationTasks, (task: MigrationTask) => {
        ListItem() {
          Column() {
            Text(task.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#17202A')
            Text(task.source)
              .fontSize(12)
              .fontColor('#667085')
              .margin({ top: 6 })
            Row() {
              Text(task.target)
                .fontSize(12)
                .fontColor('#40566F')
                .layoutWeight(1)
              Text(task.status)
                .fontSize(12)
                .fontColor(task.status.startsWith('started') || task.status.startsWith('done') ? '#0A6B45' : '#6B7280')
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Color.White)
          .borderRadius(6)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 16 })
  }
}

function createEmptyGallery(): GalleryInfo {
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

function createEmptyDownloadInfo(): DownloadInfo {
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

function createDetailFromGallery(gallery: GalleryInfo): GalleryDetail {
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

function createEmptyDetail(): GalleryDetail {
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

function createEmptyPreview(): GalleryPreview {
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

function createEmptyPage(): GalleryPage {
  return {
    pageUrl: '',
    imageUrl: '',
    skipHathKey: '',
    originImageUrl: '',
    showKey: ''
  };
}

function createEmptyTopListDetail(): TopListDetail {
  return {
    title: '',
    lists: []
  };
}

function createEmptyTopListInfo(): TopListInfo {
  return {
    kind: TopListKind.Gallery,
    title: 'Gallery Toplists',
    buckets: []
  };
}

function createEmptyTopListBucket(): TopListBucket {
  return {
    title: '',
    follow: '',
    items: []
  };
}

function createEmptyTopListItem(): TopListItem {
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

function cloneGalleryInfo(gallery: GalleryInfo): GalleryInfo {
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

function cloneGalleryInfos(galleries: GalleryInfo[]): GalleryInfo[] {
  const result: GalleryInfo[] = [];
  for (let i = 0; i < galleries.length; i++) {
    result.push(cloneGalleryInfo(galleries[i]));
  }
  return result;
}

function padTwo(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

function applyGalleryFilters(galleries: GalleryInfo[]): GalleryInfo[] {
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
      tags: cloneRequiredStringArray(groups[i].tags)
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
      score: comments[i].score
    });
  }
  return result;
}

function cloneGalleryPreviews(previews: GalleryPreview[]): GalleryPreview[] {
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

function cloneGalleryDetail(detail: GalleryDetail): GalleryDetail {
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

function cloneGalleryPage(page: GalleryPage): GalleryPage {
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

function createReaderLoadingPage(pageUrl: string): GalleryPage {
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

function cloneTopListDetail(detail: TopListDetail): TopListDetail {
  const lists: TopListInfo[] = [];
  for (let i = 0; i < detail.lists.length; i++) {
    lists.push(cloneTopListInfo(detail.lists[i]));
  }
  return {
    title: detail.title,
    lists: lists
  };
}

function getAbilityContext(): common.UIAbilityContext | undefined {
  return AppStorage.get<common.UIAbilityContext>('abilityContext');
}

function saveGalleryToHistory(gallery: GalleryInfo): void {
  const maxSize = parseHistoryMaxSize(ehSettingsStore.getValue('history_info_size', '100'));
  ehHistoryStore.addGallery(gallery, maxSize);
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehHistoryStore.save(context).catch(() => {});
}

function saveGalleryReadPosition(gid: number, pageIndex: number): void {
  ehHistoryStore.setReadPage(gid, pageIndex);
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehHistoryStore.save(context).catch(() => {});
}

function readerStartIndex(detail: GalleryDetail): number {
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

function downloadButtonText(gid: number): string {
  return ehDownloadStore.contains(gid) ? 'Queued' : 'Download';
}

function toggleGalleryDownload(gallery: GalleryInfo): boolean {
  if (ehDownloadStore.contains(gallery.gid)) {
    ehDownloadStore.removeGallery(gallery.gid);
    saveDownloadsQuietly();
    return false;
  }

  ehDownloadStore.addGallery(gallery, '');
  saveDownloadsQuietly();
  return true;
}

function saveDownloadsQuietly(): void {
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  ehDownloadStore.save(context).catch(() => {});
}

function filterDownloadItems(items: DownloadInfo[], query: string, statusFilter: string, labelFilter: string,
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

function downloadItemMatches(item: DownloadInfo, query: string): boolean {
  const title = item.title.toLowerCase();
  const uploader = item.uploader === undefined ? '' : item.uploader.toLowerCase();
  const label = item.label.toLowerCase();
  return title.indexOf(query) >= 0 || uploader.indexOf(query) >= 0 || label.indexOf(query) >= 0 ||
    item.gid.toString().indexOf(query) >= 0;
}

function sortDownloadItems(items: DownloadInfo[], sortMode: string): void {
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

function nextDownloadStatusFilter(current: string): string {
  const options: string[] = ['All', 'Idle', 'Waiting', 'Downloading', 'Downloaded', 'Failed'];
  return nextStringOption(current, options);
}

function nextDownloadLabelFilter(current: string, labels: DownloadLabel[]): string {
  const options: string[] = ['All', 'Default'];
  for (let i = 0; i < labels.length; i++) {
    options.push(labels[i].label);
  }
  return nextStringOption(current, options);
}

function nextDownloadSortMode(current: string): string {
  const options: string[] = ['Default', 'GID asc', 'GID desc', 'Rating desc', 'Name asc', 'Name desc'];
  return nextStringOption(current, options);
}

function nextStringOption(current: string, options: string[]): string {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === current) {
      return options[(i + 1) % options.length];
    }
  }
  return options.length > 0 ? options[0] : current;
}

function nextDownloadState(current: DownloadState): DownloadState {
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

function nextDownloadLabel(current: string, labels: DownloadLabel[]): string {
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

function downloadStateLabel(state: DownloadState): string {
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

function downloadStateColor(state: DownloadState): string {
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

function downloadProgressText(item: DownloadInfo): string {
  const total = item.total > 0 ? item.total : item.pages;
  if (total <= 0) {
    return '-';
  }
  return item.finished.toString() + '/' + total.toString();
}

function downloadSizeText(size: number): string {
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

function downloadImageUrlForPage(page: GalleryPage): string {
  if (ehSettingsStore.getValue('download_origin_image', 'Off') === 'On' && page.originImageUrl.length > 0) {
    return page.originImageUrl;
  }
  return page.imageUrl;
}

function downloadThreadLimit(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('download_thread', '3'));
  if (Number.isNaN(value) || value <= 0) {
    return 1;
  }
  return Math.max(1, Math.min(value, 10));
}

function downloadPageIndexes(count: number): number[] {
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

function downloadQueueSummary(items: DownloadInfo[]): string {
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

function parseHistoryMaxSize(value: string): number {
  const parsed = Number.parseInt(value);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return 100;
  }
  return parsed;
}

function routeTitle(route: GalleryRoute): string {
  for (let i = 0; i < DRAWER_ITEMS.length; i++) {
    if (DRAWER_ITEMS[i].route === route) {
      return DRAWER_ITEMS[i].title;
    }
  }
  return 'EhViewer';
}

function routeSubtitle(route: GalleryRoute): string {
  for (let i = 0; i < DRAWER_ITEMS.length; i++) {
    if (DRAWER_ITEMS[i].route === route) {
      return DRAWER_ITEMS[i].subtitle;
    }
  }
  return '';
}

function launchRouteFromSetting(value: string): GalleryRoute {
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

function settingsPanelTitle(panel: SettingsPanel): string {
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

function settingsRowsForPanel(panel: SettingsPanel, themeName: string, entries: SettingEntry[]): SettingsRowItem[] {
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
      optionSettingsRow('app_language', 'App language', 'Language override', entries, ['zh-CN', 'System', 'English', 'Japanese']),
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
      staticSettingsRow('version', 'Version', 'HarmonyOS port workspace version', '1.3.1', 'version'),
      staticSettingsRow('check_for_updates', 'Check for updates', 'Original AppUpdater entry', 'Open', 'action'),
      optionSettingsRow('close_auto_updates', 'Close automatic updates', 'Disable startup update check', entries, ON_OFF_OPTIONS),
      staticSettingsRow('donate', 'Donate', 'Original donation entry', 'Not migrated', 'url')
    ];
  }

  return [staticSettingsRow('theme', 'Theme', 'Current staged theme', themeName, 'list')];
}

const ON_OFF_OPTIONS: string[] = ['On', 'Off'];

function optionSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], options: string[]): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: settingEntryValue(entries, key, options.length > 0 ? options[0] : ''),
    type: options.length === 2 && options[0] === 'On' && options[1] === 'Off' ? 'switch' : 'list',
    options: options
  };
}

function textSettingsRow(key: string, title: string, summary: string, entries: SettingEntry[], fallback: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: settingEntryValue(entries, key, fallback),
    type: 'input'
  };
}

function staticSettingsRow(key: string, title: string, summary: string, value: string, type: string): SettingsRowItem {
  return {
    key: key,
    title: title,
    summary: summary,
    value: value,
    type: type
  };
}

function settingEntryValue(entries: SettingEntry[], key: string, fallback: string): string {
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].key === key) {
      return entries[i].value;
    }
  }
  return fallback;
}

function cloneStringOptions(options: string[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < options.length; i++) {
    result.push(options[i]);
  }
  return result;
}

function settingMigrationMessage(key: string): string {
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

function nextOption(current: string, options: string[]): string {
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

function isValidProxyPortText(value: string): boolean {
  const port = Number.parseInt(value);
  return !Number.isNaN(port) && port > 0 && port <= 65535 && port.toString() === value.trim();
}

function formatNetworkDiagnostics(results: NetworkDiagnosticResult[]): string {
  const parts: string[] = [];
  for (let i = 0; i < results.length; i++) {
    const item = results[i];
    const status = item.statusCode > 0 ? item.statusCode.toString() : 'ERR';
    parts.push(item.label + ' ' + status + ' ' + item.elapsedMs.toString() + 'ms' +
      (item.ok ? '' : ' ' + item.message));
  }
  return 'Network diagnostics: ' + parts.join(' | ');
}

function listModeForRoute(route: GalleryRoute): ListMode {
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

function routeUsesKeyword(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription || route === GalleryRoute.Favorites;
}

function usesGallerySearchToolbar(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription ||
    route === GalleryRoute.WhatsHot || route === GalleryRoute.Favorites;
}

function usesEmbeddedToolbar(route: GalleryRoute): boolean {
  return usesGallerySearchToolbar(route) || route === GalleryRoute.TopLists || route === GalleryRoute.History ||
    route === GalleryRoute.Downloads || route === GalleryRoute.Settings || route === GalleryRoute.Session;
}

function defaultKeywordForRoute(route: GalleryRoute): string {
  return '';
}

function gallerySearchTitle(route: GalleryRoute, keyword: string, filterActive: boolean): string {
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

function currentGallerySite(): GallerySite {
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
}

function effectiveListSite(route: GalleryRoute): GallerySite {
  const site = currentGallerySite();
  if (site === GallerySite.Ex && !ehCookieStore.hasCookies() && route !== GalleryRoute.Favorites &&
    route !== GalleryRoute.Subscription) {
    return GallerySite.E;
  }
  return site;
}

function gallerySiteName(site: GallerySite): string {
  return site === GallerySite.Ex ? 'ExHentai' : 'E-Hentai';
}

function galleryListFailureMessage(result: GalleryListLoadResult, site: GallerySite): string {
  const status = result.statusCode > 0 ? 'HTTP ' + result.statusCode.toString() + ', ' : '';
  const url = result.url.length > 0 ? ', ' + result.url : '';
  return 'Load failed: ' + gallerySiteName(site) + ', ' + status + result.message + url;
}

function shouldRetryGalleryListOnE(result: GalleryListLoadResult, site: GallerySite, route: GalleryRoute): boolean {
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

function withGalleryListMessage(result: GalleryListLoadResult, message: string): GalleryListLoadResult {
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

function readerPageReferer(detailUrl: string, previews: GalleryPreview[], index: number, site: GallerySite): string {
  if (index > 0 && index - 1 < previews.length && previews[index - 1].pageUrl.length > 0) {
    return previews[index - 1].pageUrl;
  }
  if (detailUrl.length > 0) {
    return detailUrl;
  }
  return EhUrl.getReferer(site);
}

function readerDisplayImageUrl(page: GalleryPage, preferOriginal: boolean): string {
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

function cacheReaderImageForPage(page: GalleryPage, onReady: (page: GalleryPage) => void): void {
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

function cacheThumbnailImage(url: string, onReady: (path: string) => void): void {
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

function readerLocalImageSource(path: string): string {
  return path.startsWith('file://') ? path : 'file://' + path;
}

function readerZoomSize(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

function readerFullImageWidth(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

function readerFullImageHeight(zoomPercent: number): string {
  return zoomPercent.toString() + '%';
}

function readerImageFit(fitMode: string): ImageFit {
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

function readerShortUrl(url: string): string {
  if (url.length <= 96) {
    return url;
  }
  return url.substring(0, 72) + '...' + url.substring(url.length - 18);
}

function readerPreloadCount(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('preload_image', '5'));
  if (Number.isNaN(value) || value <= 0) {
    return 0;
  }
  return Math.min(value, 3);
}

function readerIsRightToLeft(): boolean {
  return ehSettingsStore.getValue('reading_direction', 'Left to right') === 'Right to left';
}

function categoryName(category: number): string {
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

function categoryColor(category: number): string {
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

function ratingText(rating: number): string {
  return rating < 0 ? '-' : rating.toString();
}

function galleryDisplayTitle(gallery: GalleryInfo): string {
  if (ehSettingsStore.getValue('show_jpn_title', 'Off') === 'On' &&
    gallery.titleJpn !== undefined && gallery.titleJpn.length > 0) {
    return gallery.titleJpn;
  }
  return gallery.title.length === 0 ? 'Untitled' : gallery.title;
}

function showGalleryPages(): boolean {
  return ehSettingsStore.getValue('show_gallery_pages', 'Off') === 'On';
}

function galleryListMode(): string {
  return ehSettingsStore.getValue('list_mode', 'Detail');
}

function galleryThumbWidth(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Large');
  if (value === 'Small') {
    return 70;
  }
  if (value === 'XLarge') {
    return 104;
  }
  return 86;
}

function galleryThumbHeight(): number {
  const value = ehSettingsStore.getValue('thumb_size', 'Large');
  if (value === 'Small') {
    return 96;
  }
  if (value === 'XLarge') {
    return 142;
  }
  return 118;
}

function galleryRowHeight(): number {
  const height = galleryThumbHeight();
  if (galleryListMode() === 'Thumb') {
    return height;
  }
  if (galleryListMode() === 'Extended') {
    return Math.max(height, 134);
  }
  return height;
}

function galleryTagPreview(gallery: GalleryInfo): string {
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

function detailTitleFontSize(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Default');
  if (value === 'Compact') {
    return 16;
  }
  if (value === 'Large') {
    return 20;
  }
  return 18;
}

function detailTitleMaxLines(): number {
  const value = ehSettingsStore.getValue('detail_size', 'Default');
  if (value === 'Compact') {
    return 3;
  }
  if (value === 'Large') {
    return 6;
  }
  return 5;
}

function detailHeadingFontSize(): number {
  return ehSettingsStore.getValue('detail_size', 'Default') === 'Large' ? 16 : 15;
}

function readerShowProgress(): boolean {
  return ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
}

function readerShowClock(): boolean {
  return ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
}

function readerClockText(): string {
  const now = new Date();
  return padTimeNumber(now.getHours()) + ':' + padTimeNumber(now.getMinutes());
}

function padTimeNumber(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function topListChipColor(index: number): string {
  const colors: string[] = ['#2F6F8F', '#7A5A22', '#327A5B', '#A04462', '#4D6D8C', '#805A8F', '#8A4F2B', '#556B2F', '#6B7280', '#1F6B63'];
  return colors[index % colors.length];
}
