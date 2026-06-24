# EhViewer HarmonyOS

<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" alt="EhViewer HarmonyOS app icon" />
</p>

`Ehviewer_OHOS` 是基于 `Ehviewer_CN_SXJ` 的 HarmonyOS 原生移植项目。目标不是运行 Android APK 或兼容层，而是使用 ArkTS、ArkUI、Stage 模型和 HarmonyOS 原生能力重写 EhViewer 的主要界面、网络、阅读器、下载、历史和设置逻辑。

当前目标环境：

- HarmonyOS 6.1.0
- API 6.1.1 (24)
- Bundle：`yt.ehviewer.huawei`
- 技术栈：ArkTS + ArkUI + Stage 模型
- 当前版本：`0.3.28`

## 预览

<p align="center">
  <img src="docs/images/gallery-list.jpg" width="280" alt="Gallery list screenshot" />
  <img src="docs/images/gallery-detail.jpg" width="280" alt="Gallery detail screenshot" />
</p>

## 当前状态

这是一个仍在快速迭代中的移植版本。主流程已经可以运行，但仍不等同于原 Android 应用的完整复刻。界面、交互、网络细节、解析兼容性、后台任务能力和设备适配会继续参考 `Ehviewer_CN_SXJ` 修正。

已重点迁移的能力包括：

- 原生 HarmonyOS 页面框架、抽屉导航和多页面入口。
- E-Hentai / ExHentai 基础浏览、搜索、详情、预览、评论、收藏、评分和阅读流程。
- 阅读器横向、竖向连续阅读、缩放、平移、预加载、进度条、时间、电量、亮度和音量键翻页。
- 登录、Cookie、WebView 会话捕获和基础网络诊断。
- 下载队列、本地文件输出、下载恢复、历史记录、过滤规则和设置持久化。

## 已实现功能

### 页面与导航

- 首页、订阅、热门、排行、收藏、历史、下载、设置等主要入口。
- 接近原 Android 应用的抽屉导航结构。
- 亮色、暗色、黑色主题切换。
- 简体中文、英文和跟随系统语言。

### 画廊浏览

- E-Hentai / ExHentai 站点切换。
- 画廊列表加载、刷新、分页和搜索。
- 列表显示模式：详情、缩略图、扩展模式。
- 分类、标题、上传者、评分、页数、语言、标签等基础信息解析。
- 详情页元数据、标签、预览图、评论入口。
- 标签翻译显示，使用 EhTagTranslation 数据库。
- 收藏添加/移除、评分提交。
- 历史记录保存、打开、删除和清空。

### 登录与会话

- 账号密码登录。
- Cookie 查看和导入。
- WebView 登录与 Cookie 同步。
- 游客模式。
- Cookie 持久化和请求时自动附带。

### 网络

- 基于 HarmonyOS `@kit.NetworkKit` 的 GET、POST 表单、POST JSON 请求。
- Cookie、Referer、Origin、User-Agent 等请求头处理。
- 文本请求并发限制、短缓存、重复请求合并和瞬时错误重试。
- `gdata` 和 `showpage` API 快速路径。
- 系统代理、关闭代理、自定义 HTTP/SOCKS 代理。
- 内置 E-Hentai / ExHentai hosts 规则。
- DNS over HTTPS。
- API 23+ `sniHostName` 域名前置逻辑。
- 网络诊断入口，可检测 E、EX、Forums、Repo 连通性。

### 阅读器

- 独立阅读器 Ability 和内嵌阅读器。
- 横向左到右、横向右到左、竖向连续阅读。
- 实际尺寸、适合宽度、适合高度、适合屏幕、固定比例等适配模式。
- 起始位置、屏幕旋转、匹配图片方向、全屏阅读。
- 单指拖动、双击缩放、双指缩放、惯性平移。
- 竖向模式放大后横向溢出时，所有图片共享横向偏移，保持首尾连续。
- 阅读器操作区域绑定屏幕，而不是绑定图片显示区域。
- 右上角时间、进度、电量显示，避开系统避让区。
- 底部进度条、拖动页码气泡和自动翻页控制。
- 音量键翻页；竖向模式下上一页/下一页对应滚动 0.8 屏。
- 原图切换、重试、刷新当前图片、分享图片。
- 长按图片菜单：刷新、分享、保存到图库、保存到指定位置。
- 阅读器背景、保持屏幕常亮、自定义亮度、超暗模式。

### 下载与本地存储

- 下载队列、标签、状态过滤、分类过滤和排序。
- 多线程下载设置。
- 下载原图设置、下载超时设置、升序/降序下载。
- 下载进度、速度、已下载大小显示。
- 应用内部目录和公共 Downloads 目录。
- 已下载文件夹恢复下载项。
- 清理冗余下载目录。
- 已下载内容本地阅读。
- 导出选中下载为 ZIP。

### 设置与数据

- EH、阅读、下载、隐私、高级、关于等设置面板。
- UConfig、My Tags WebView 入口。
- 过滤/黑名单规则本地管理，并应用到列表。
- 数据导出/导入：Cookie、设置、历史、下载、过滤规则。
- 防截屏安全窗口。
- 前台恢复时的系统认证/生物识别保护。
- 阅读缓存大小、内存缓存清理、下载路径缓存刷新。
- 迁移状态查看。

## 仍在完善

- 解析器仍需要覆盖更多边缘页面、错误页面和站点布局变化。
- 下载目前以应用前台队列为主，后台长期任务能力仍需继续补齐。
- Wi-Fi 传输、捐赠、Android logcat 等原应用入口尚未完整迁移。
- 部分系统图标、系统权限和媒体库行为依赖设备固件版本。
- UI 细节仍会继续对照原应用修正。

## 构建

需要安装 DevEco Studio，并使用项目目标 SDK。当前常用构建命令：

```powershell
& "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode project -p product=default assembleApp --analyze=normal --parallel --incremental --daemon
```

常见产物路径：

- HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- APP：`build/outputs/default/Ehviewer_OHOS-default-signed.app`

本地签名配置通常在 `build-profile.json5`，不要把个人签名口令提交到仓库。

## 目录结构

- `AppScope/`：应用级配置、图标和名称资源。
- `entry/src/main/module.json5`：Entry 模块、权限和 Ability 配置。
- `entry/src/main/ets/pages/`：页面入口。
- `entry/src/main/ets/components/`：ArkUI 页面、列表、详情、阅读器、下载、设置组件。
- `entry/src/main/ets/components/reader/`：阅读器核心、菜单、覆盖层、图片视口和图片文件操作。
- `entry/src/main/ets/services/`：网络、Cookie、下载、历史、缓存、设置、解析器等服务。
- `entry/src/main/ets/model/`：画廊、页面、下载、排行等数据模型。
- `entry/src/main/ets/shared/`：共享 UI 文案、主题、设置项和工具函数。
- `entry/src/main/resources/`：应用资源。
- `docs/images/`：README 截图资源。

## 反馈

欢迎通过 Issue 反馈问题。为了提高修复效率，请尽量提供：

- 具体页面和操作步骤。
- 站点类型：E-Hentai 或 ExHentai。
- 阅读方向、缩放模式、网络设置等相关配置。
- 复现截图、录屏或日志。
- 如果是解析问题，请说明列表页、详情页、图片页或下载流程。

## 致谢

感谢 `Ehviewer_CN_SXJ` 及相关 EhViewer 项目的作者和贡献者。本项目的界面、功能和逻辑均大量参考原应用。

感谢 [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) 项目维护中文标签翻译数据。

也感谢所有测试、反馈问题、提出建议和提交修复的用户。

## License

本项目按 `GPL-3.0-or-later` 发布。移植过程中新增代码也使用相同许可。
