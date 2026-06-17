# EhViewer HarmonyOS

`Ehviewer_OHOS` 是基于 `Ehviewer_CN_SXJ` 的 HarmonyOS 原生移植项目。项目目标不是通过 Android 兼容层运行 APK，而是使用 ArkTS、ArkUI 和 HarmonyOS Stage 模型重写主要界面、网络、阅读器、下载、历史、设置等功能。

当前目标环境：

- HarmonyOS 6.1.0
- API 6.1.1 (24)
- 包名：`yt.ehviewer.huawei`
- 技术栈：ArkTS + ArkUI + Stage 模型

## 项目说明

这是一个仍在快速迭代中的移植版本，功能、交互和布局会持续参考原 Android 应用进行补齐和修正。目前主要页面和核心流程已经可以运行，但仍可能存在解析不完整、界面细节不一致、设备适配不足、阅读器/下载/设置行为不完善等问题。

本应用完全由 AI 编程完成，并在使用过程中持续快速修正。如果一段时间没有更新，大概率是额度、token 或上下文都用完了，不一定是项目停止了。

欢迎通过 Issue 反馈 bug、提出建议，也欢迎直接帮忙修 bug、补功能、改 UI。能复现的问题请尽量附上页面、操作步骤、站点类型、日志或截图，这会让修复快很多。

## 已迁移内容

- 主页、订阅、热门、排行、收藏、历史、下载、设置等主要入口。
- 画廊列表、搜索、刷新、分页、详情页、标签、评论入口等基础浏览流程。
- 阅读器页面，包括独立阅读器、翻页、缩放、适配模式、进度条、自动翻页、阅读设置等。
- 登录相关流程，包括账号密码、Cookie、WebView 和游客模式。
- 本地历史、下载队列、阅读缓存、图片缓存和基础设置持久化。
- E-Hentai / ExHentai 的基础网络请求、Cookie、Referer、列表/详情/图片页解析逻辑。

## 构建方式

推荐使用 DevEco Studio 打开项目目录，并保持 SDK 目标为 `6.1.1 (24)`。

命令行构建示例：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:OHOS_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode project -p product=default assembleApp --analyze=normal --parallel --incremental --daemon
```

常见构建产物：

- `entry/build/default/outputs/default/entry-default-unsigned.hap`
- `entry/build/default/outputs/default/app/entry-default.hap`

当前仓库未配置正式签名文件，构建日志中出现跳过签名的提示属于预期行为。

## 目录结构

- `AppScope/`：应用级配置、图标和名称资源。
- `entry/src/main/ets/pages/`：页面入口。
- `entry/src/main/ets/components/`：ArkUI 页面和组件。
- `entry/src/main/ets/services/`：网络、Cookie、下载、历史、缓存、设置等服务。
- `entry/src/main/ets/parser/`：列表页、详情页、图片页、排行页解析逻辑。
- `entry/src/main/ets/model/`：画廊、下载、设置等数据模型。
- `entry/src/main/resources/`：模块资源和语言资源。

## 反馈与贡献

欢迎：

- 提交 bug 复现步骤。
- 帮忙测试不同设备和不同 HarmonyOS 版本。
- 修复解析、网络、布局、阅读器、下载、设置等问题。
- 补充更接近原应用的交互细节。
- 改善文档、翻译和无障碍体验。

如果提交代码，请尽量保持改动聚焦，避免把无关格式化和功能修改混在一起。

## 致谢

感谢 `Ehviewer_CN_SXJ` 及相关 EhViewer 项目的作者和贡献者。这个移植项目的界面、功能和逻辑都大量参考了原应用。

也感谢所有测试、反馈问题、提出建议和愿意帮忙修 bug 的用户。快速迭代离不开这些真实反馈。

## License

本项目继承原项目的开源许可约束，按 `GPL-3.0-or-later` 发布。移植过程中新增的代码也按相同许可发布。
