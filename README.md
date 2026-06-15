# EhViewer HarmonyOS 移植版

这是 `Ehviewer_CN_SXJ` 的 HarmonyOS 原生移植工程。目标不是通过 Android 兼容层运行 APK，而是使用 ArkTS、ArkUI 和 HarmonyOS Stage 模型重写主要界面、网络、阅读器、下载和设置逻辑。

## 目标环境

- HarmonyOS：6.1.0
- API：6.1.1(24)
- 应用包名：`yt.ehviewer.huawei`
- 开发范式：ArkTS + ArkUI 声明式 UI
- 工程模型：Stage 模型
- 版本起点：`0.1.0`

## 当前状态

当前工程已经从最初的壳应用推进到可运行的原生移植版本，主要页面和核心流程已经接入前端，不再只是占位界面。

已迁移或部分迁移的能力：

- 左侧抽屉：首页、订阅、热门、排行、收藏、历史、下载、设置。
- 首页/订阅/热门/收藏：通过共享画廊列表逻辑加载远端列表，支持搜索、刷新、翻页、详情跳转和右下角快捷操作。
- 详情页：显示标题、封面、元数据、标签、评论入口、下载、阅读等操作。
- 阅读器：独立全屏阅读界面，支持上一页、下一页、跳页、重试、缩放、适配模式、原图/重采样切换、阅读方向和预加载。
- 网络层：基于 HarmonyOS HTTP API 实现文本请求、Cookie、Referer、列表/详情/图片页加载、请求合并、短期缓存和 E 站/Ex 站回退逻辑。
- 登录：支持账号密码登录、WebView 登录、Cookie 登录和访客模式。
- 设置：按原应用层级迁移 EH、阅读、下载、隐私、高级、关于等设置；多选项和二值选项已接入持久化。
- 隐私：迁移安全屏幕逻辑，使用 HarmonyOS 隐私窗口能力减少截屏风险。
- 历史：本地记录成功打开过的画廊详情，支持列表查看、重新打开、删除和清空。
- 下载：支持队列、标签、筛选、排序、开始/停止、进度、断点跳过已有页、文件落盘和完成清理。
- 排行：加载 E-Hentai 排行页，支持分类切换、排行项打开和画廊列表周期入口。
- 多语言：本体以英文资源为主，提供中文语言资源，并跟随系统/应用语言状态刷新。
- 图标：已重新设计 HarmonyOS 应用图标。

仍需继续完善的方向：

- 更多原应用设置项与运行时行为的完整绑定。
- ArkWeb 登录遇到浏览器挑战时的恢复策略。
- 下载任务迁移到更完整的 HarmonyOS 后台任务模型。
- 更完整的异常页面、重试策略和设备端解析测试。
- 归档导入/导出、更多本地文件管理和原生解码能力。

## 构建方式

推荐使用 DevEco Studio 打开本目录，SDK 目标保持 `6.1.1(24)`。

当前工作站命令行构建示例：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='D:\Program Files\Huawei\DevEco Studio\jbr\bin;' + $env:Path
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp --no-daemon
```

构建产物通常位于：

- HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 打包后的 HAP：`entry/build/default/outputs/default/app/entry-default.hap`
- APP：`build/outputs/default/Ehviewer_OHOS-default-unsigned.app`

当前仓库未配置正式签名文件，因此构建日志中出现跳过签名的提示属于预期行为。

## 目录说明

- `AppScope/`：应用级配置、应用图标和应用名称资源。
- `entry/src/main/ets/pages/`：入口页面。
- `entry/src/main/ets/components/`：ArkUI 页面和复用组件。
- `entry/src/main/ets/services/`：网络、Cookie、下载、历史、缓存等服务。
- `entry/src/main/ets/parser/`：画廊列表、详情页、图片页、排行页解析。
- `entry/src/main/ets/model/`：画廊、下载、设置等数据模型。
- `entry/src/main/resources/`：模块资源和语言包。

## 发布说明

本仓库的版本号从 `0.1.0` 开始递增。只有在实现新功能、用户明确要求发布，或需要交付可安装包时才创建 GitHub Release；普通 bug 修复不默认发布 Release。

### v0.1.32

- 画廊列表解析器新增显示模式自动识别。
- 分别适配 Minimal、Minimal+、Compact、Extended、Thumbnail 五种列表结构。
- 补充 Compact 和 Minimal+ 离线解析样本。

### v0.1.31

- 应用包名改为 `yt.ehviewer.huawei`。
- README 全面改写为中文说明。
- 发布构建产物到 GitHub Release。

### v0.1.30

- 重新设计应用图标。
- 替换 AppScope 和 entry 两处 `app_icon.png`。

### v0.1.29

- 封装共享浮动标题栏宿主。
- 首页/画廊、历史、排行页面复用同一标题栏结构。
- 收紧画廊顶部间距，修正历史页顶部白条。

### v0.1.28

- 修正上滑隐藏标题栏后，下滑不能立即恢复的问题。
- 画廊、历史、排行页面统一按滚动方向恢复标题栏。

## 许可

本工程继承原项目 GPL-3.0-or-later 许可约束。移植过程中的新增代码同样按该许可发布。
