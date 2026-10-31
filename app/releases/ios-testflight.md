# iOS TestFlight 与跨端功能

首个上传构建：0.1.0 (1)，Bundle ID `work.ianvs.linefold`，App Store Connect App ID `6829149506`。
iOS 与 macOS 均使用 iCloud Documents 容器 `iCloud.work.ianvs.linefold`；生产分发不能使用开发环境容器。
macOS 0.1.0 是本地模式；从 0.1.1 起，GitHub 发布包携带 Developer ID iCloud 描述文件。

| 能力 | macOS | iOS |
| --- | --- | --- |
| Markdown、表格、公式、Mermaid 阅读 | 支持 | 支持 |
| 编辑保存 | Live Preview / Source / Read | 预览 → 铅笔按钮 → 源码编辑 → 保存 |
| 保存保护 | 外部修改检测、草稿恢复 | 外部修改检测、草稿恢复；恢复草稿不会自动覆盖文件 |
| 默认 vault | iCloud · Linefold | iCloud · Linefold；不可用时明确提示本机模式 |
| 接收 .md | 文件关联、拖入、Quick Look | 文档类型注册和 Open In / 文件附件分享；导入副本 |
| 原文件编辑 | 用户选择文件/文件夹 | 用户明确选择整个文件夹后获得写入权限 |
| 查找与导航 | 工作区全文搜索/替换、目录、链接 | 文件名过滤、当前文档查找、目录、Markdown/Wiki 链接与返回 |
| 图片 | 完整桌面附件流程 | 读取授权文件夹内的本地图片 |
| 高级整理与导出 | 模板、集合、批量移动、导出 | 未对齐桌面完整能力 |

iOS 注册的是 Markdown 文档接收入口，没有独立的文本/网页 Share Extension。
分享导入只编辑应用内副本，不能把“保存”理解为修改发送方的原文件。
两端使用同一 Apple Account 并打开 iCloud Drive。默认云端文件由系统同步；本地外部工作区不会自动上传。
iOS 会迁移旧的 Imports 副本；本机根目录新建的笔记需要手动转入云端，不能把这项迁移视为完整双向同步。

## 重复上传

本机 Xcode Accounts 登录团队后，需要 Apple Distribution 证书及私钥；首次上传已通过自动签名生成对应描述文件。
在 app 中运行 `flutter build ios --release --no-codesign --config-only`，然后从仓库根目录归档：

```sh
CARGO_PROFILE_RELEASE_STRIP=none xcodebuild \
  -workspace app/ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath app/build/ios/archive/Linefold.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=UT9BL9NZPG \
  CODE_SIGN_STYLE=Automatic LINEFOLD_CLOUD_ENABLED=YES archive
xcodebuild -exportArchive \
  -archivePath app/build/ios/archive/Linefold.xcarchive \
  -exportOptionsPlist app/ios/TestFlightExportOptions.plist \
  -exportPath app/build/ios/testflight -allowProvisioningUpdates
```

每次上传必须增加 `app/pubspec.yaml` 的构建号。版本由 Flutter config-only 生成到 Xcode 配置。
上传成功仍需等 Apple 处理完成，并把构建添加到内部测试组；外部测试另需 Beta App Review。
不把 Apple Account 密码、证书私钥或 App 专用密码提交仓库。

## 验证记录与边界

- iOS 原生导入、受保护写入及预览测试已运行；发布改动后的 37 项预览/工作区回归通过。
- iOS 签名 Archive、App Store Connect 上传成功；模拟器实际新建、编辑、保存后核对磁盘内容一致。
- macOS Release 构建、带描述文件的 Developer ID 深层签名校验通过；实际启动默认显示 iCloud · Linefold。
- iOS 模拟器未登录 iCloud，不能代替两台真实设备上同步延迟、离线重连和冲突场景的验收。
- 首个上传有 MermanFFI.framework 缺少 dSYM 的非阻断警告；该库崩溃报告的符号解析不完整。

隐私清单依据 Apple 的 required-reason API 文档声明应用容器/用户授权文件元数据、写入容量检查及自身 UserDefaults：
https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
应用不实现自有加密；CryptoKit/SHA256 用于文件完整性，云端连接使用系统服务。
