# EhViewer HarmonyOS

[English](README_EN.md) · 简体中文

<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" alt="EhViewer HarmonyOS 应用图标" />
</p>

这是 [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) 的 HarmonyOS 移植版本，面向手机、平板、折叠屏和电脑提供画廊浏览、搜索、阅读、下载、翻译与数据迁移功能。

## 下载与安装

请在 [GitHub Releases](https://github.com/suibianqwe/Ehviewer_OHOS/releases) 下载最新的未签名 HAP，可使用 [小白调试助手](https://github.com/likuai2010/auto-installer) 安装。

- 当前版本：`0.7.2`
- 安装包：[`EhViewer_OHOS_0.7.2.hap`](https://github.com/suibianqwe/Ehviewer_OHOS/releases/download/v0.7.2/EhViewer_OHOS_0.7.2.hap)
- 目标 API：`26.0.0`
- 兼容 API：`6.0.0(20)`

API 20 起可安装；低于 API 23 的设备会自动跳过不兼容的 SNI 域名前置增强。

## 使用教程

初次使用、登录、搜索、分栏、阅读器、漫画翻译、下载恢复、网络设置和数据迁移等操作，请查看：

### [EhViewer HarmonyOS 完整使用教程](docs/USER_GUIDE.md)

也可阅读 [English User Guide](docs/USER_GUIDE_EN.md)。教程包含目录、分章节步骤、手机/平板实机截图、常见问题和日志导出说明。

> 图片或封面无法加载时，请先进入 `设置 → EH → 账号配置`，等待账号配置页面加载后返回，让应用重新获取当前站点配置；再回到原页面重试。

## 功能特色

- 浏览：支持 E-Hentai/ExHentai、主页、订阅、热门、排行、云端收藏、本地收藏、历史和下载列表。
- 搜索：支持关键词、多标签、上传者、高级筛选、搜索书签、搜索历史、相似图片和封面搜索。
- 详情：支持收藏、评分、系统分享、Torrent 磁力链接、存档、H@H、评论、预览图、相似画廊、标签编辑和投票。
- 阅读：支持左右/连续阅读、阅读预设、双击与手势缩放、方向适配、自适应一屏双页、白边裁切、预加载、覆盖式内嵌阅读器和独立全屏阅读器。
- 图像增强：支持图像调节、自适应去除摩尔纹、系统/API 26 Core Vision AI 超分及 SDR 转 HDR；在预渲染阶段按“去摩尔纹与图像调节 → 超分 → HDR”顺序组合处理。
- 翻译：支持列表标题、详情标题、评论及漫画 OCR 翻译，可选网页翻译、DeepSeek、OpenAI、Gemini 和自定义兼容 API。
- 下载：支持统一优先级并行调度、通知进度与速度、隐私通知、状态筛选、多选管理、恢复下载项和 ZIP 导入/导出。
- 宽屏：支持可拖动分割线的左右分栏，列表、详情和设置页面保持独立路由与焦点返回逻辑。
- 迁移：支持 JSON/安卓数据库导入、原 EhViewer 下载目录恢复，以及阅读进度、应用设置、登录 Cookie、收藏、书签、图片文件和评论黑名单的 Wi-Fi 直连多选传输；本机 `igneous` 不会导出或被传入值覆盖。
- 个性化：支持简体中文、繁体中文、明暗主题、多种主题色、标签翻译、过滤规则、评论黑名单和隐私保护。
- 网络：支持系统/HTTP/SOCKS5 代理、DoH、内置 Hosts、SNI 域名前置、直连检测和网络诊断。

## 0.7.2 更新

- 新增远程存储（WebDAV/NAS）：服务器配置、连接检查、HTTPS 与忽略证书、自定义端口（HTTPS 默认 5006）、跟随 3xx 重定向、仅 Wi-Fi 同步，以及同步状态与进度弹窗。
- 新增多设备同步：历史、阅读进度、书签、收藏、分类、评论黑名单、过滤规则、搜索历史、阅读器预设、翻译提示词、Cookie 与设置均可同步；按分区哈希增量上传，墓碑机制避免已删除数据被旧副本恢复。
- 同步更省流量：轮询只探测 manifest 时间戳，本地无变化时只上传变化分区；历史与下载清单按 1000 条/1MB 分片存储，支持多设备合并与设备标识。
- 下载支持云端位置与镜像：可仅保存到云端；云端画廊详情页直接打开并按页读取，详情页提供「下载到本地」；镜像支持断点续传、并发上传与按大小/时间保留新文件。
- 下载删除支持本机/云端/待处理队列三种选择，云端删除失败自动重试。
- 修复下载界面全选失效，并修复历史页翻页、下载页滚动、双栏打开详情时的列表抖动与跳动。
- 详情页标签改用纯色背景，去掉逐个标签的系统材质与背景模糊，标签较多时滚动更流畅。
- 降低 WebDAV 并发并禁用连接复用，规避系统网络栈在并发请求下的崩溃。

## 0.7.1 更新

- 标准画廊列表改用 LazyForEach 懒加载并固定内容间距，减少滚动时整表重排；浮动导航栏拆为独立组件，按滚动偏移增量刷新。
- 阅读器优化分组与预取，SDR 兼容像素图创建移出主线程，长图支持分块超分；修复阅读器菜单配色与评论投票选中态。
- 重写去摩尔纹为全向纹理检测与边缘保护混合：细密网点明显抚平，线条与文字保持清晰。
- 下载页结构与首页统一（工具栏宿主、沉浸滚动、搜索模式与浮层骨架），并抽出两页公用的悬浮动作与工具栏绑定。
- 智感握持降低灵敏度：候选握持手需稳定后才切换，连续换手限流，双手或未识别时保持当前侧；主页与下载页共用同一套悬浮动作控制。
- 修复 etscheck 报告的全部 await 误用，并按检查建议消除深拷贝、循环内状态读取等性能隐患。
- 移除页面顶部与 Index 根节点的冗余层级，减少无谓渲染。

## 0.7.0 更新

- 新增「多设备流转」设置（默认关闭），开启后可在另一台设备继续当前页面，支持恢复主页路由和漫画阅读进度，内嵌与独立阅读器均支持。
- 新增搜索书签编辑，可修改名称、关键词、搜索模式、分类、过滤开关、高级搜索、评分和页码范围，保存时保留原书签 ID、排序与来源。
- 画廊卡片新增下载与收藏标记。
- 阅读器图像调节滑杆支持双击归零，覆盖曝光、亮度、对比度、亮部、暗部、清晰度、锐化、饱和度、自然饱和度、色相、色温和灰度。
- 设置页记忆滚动位置，返回或重新进入设置时恢复之前的滚动位置。
- 优化缩略图预加载、预渲染与缓存，缩短画廊首屏加载时间；页面切换时减少重复重建和深拷贝。
- 统一按钮、工具栏与弹窗的高斯模糊材质和高光边框，改善亮色主题下的对比度。
- 搜索页浮动按钮支持拖动切换左右位置；下载页滚动与工具栏行为与首页保持一致。

## 界面预览

以下截图分别来自手机竖屏和平板横屏实机；进入阅读器的示例路径为 `订阅 → 画廊详情 → 阅读`。

<table>
  <tr>
    <td><img src="docs/images/gallery-mode-detail-phone.jpg" alt="画廊详情模式" width="220" /></td>
    <td><img src="docs/images/gallery-mode-thumbnail-phone.jpg" alt="画廊缩略图模式" width="220" /></td>
    <td><img src="docs/images/gallery-mode-extended-phone.jpg" alt="画廊扩展模式" width="220" /></td>
    <td><img src="docs/images/advanced-search-phone.jpg" alt="高级搜索" width="220" /></td>
  </tr>
  <tr>
    <td align="center">详情模式</td>
    <td align="center">缩略图模式</td>
    <td align="center">扩展模式</td>
    <td align="center">高级搜索</td>
  </tr>
  <tr>
    <td><img src="docs/images/image-search-phone.jpg" alt="图片搜索" width="220" /></td>
    <td><img src="docs/images/gallery-detail-actions-phone.jpg" alt="画廊详情操作" width="220" /></td>
    <td><img src="docs/images/gallery-tag-vote-phone.jpg" alt="标签编辑与投票" width="220" /></td>
    <td><img src="docs/images/home-tablet.jpg" alt="平板横屏画廊列表" width="440" /></td>
  </tr>
  <tr>
    <td align="center">图片搜索</td>
    <td align="center">详情操作</td>
    <td align="center">标签编辑与投票</td>
    <td align="center">平板横屏画廊列表</td>
  </tr>
</table>

<table>
  <tr>
    <td><img src="docs/images/subscriptions-phone.jpg" alt="手机竖屏订阅页" width="260" /></td>
    <td><img src="docs/images/reader-layout-phone.jpg" alt="手机竖屏阅读器页面布局" width="260" /></td>
    <td><img src="docs/images/gallery-detail-tablet.jpg" alt="平板横屏订阅与详情分栏" width="520" /></td>
  </tr>
  <tr>
    <td align="center">手机订阅页</td>
    <td align="center">阅读器页面布局</td>
    <td align="center">平板分栏详情</td>
  </tr>
</table>

## 数据迁移

从原安卓 EhViewer 迁移时，可将原下载画廊目录复制到鸿蒙设备的 EhViewer 下载目录，再运行 `设置 → 下载 → 恢复下载项`。应用也能识别公共 Download 根目录中的未加密存档、应用导出包和外来画廊 ZIP。

详细步骤与路径说明见[完整教程的迁移章节](docs/USER_GUIDE.md#14-从原-ehviewer-迁移下载数据)。

## 反馈

欢迎通过 [Issues](https://github.com/suibianqwe/Ehviewer_OHOS/issues) 反馈问题。请尽量提供应用版本、设备与系统版本、复现步骤、截图/录屏和已脱敏日志。漫画翻译问题建议同时导出 OCR 调试信息。

## 致谢

感谢 [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) 和 [EhViewer](https://github.com/seven332/EhViewer) 项目的作者与贡献者。

感谢 [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) 项目维护中文标签翻译数据。

## 许可

本项目继承原应用许可证，详见 [LICENSE](LICENSE)。
