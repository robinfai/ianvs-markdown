# iOS TestFlight 与跨端功能

首个上传构建：0.1.0 (1)，Bundle ID `work.ianvs.linefold`，App Store Connect App ID `6829149506`。
iOS 与 macOS 均使用 iCloud Documents 容器 `iCloud.work.ianvs.linefold`；生产分发不能使用开发环境容器。
macOS 0.1.0 是本地模式；从 0.1.1 起，GitHub 发布包携带 Developer ID iCloud 描述文件。

| 能力 | macOS | iOS |
| --- | --- | --- |
| Markdown、表格、公式、Mermaid 阅读 | 支持 | 支持 |
| 编辑保存 | Live Preview / Source / Read | 同一编辑器，移动抽屉与紧凑工具栏 |
| 保存保护 | 外部修改检测、草稿恢复 | 外部修改检测、草稿恢复；恢复草稿不会自动覆盖文件 |
| 默认 vault | iCloud · Linefold | iCloud · Linefold；不可用时明确提示本机模式 |
| 接收 .md | 文件关联、拖入、Quick Look | 文档类型注册和 Open In / 文件附件分享；导入副本 |
| 原文件编辑 | 用户选择文件/文件夹 | 用户明确选择整个文件夹后获得写入权限 |
| 查找与导航 | 工作区全文搜索/替换、目录、链接 | 共享工作区搜索、命令面板、目录与链接 |
| 图片 | 完整桌面附件流程 | 授权文件夹内图片、导入及剪贴板图片 |
| 目录管理 | 创建、重命名、复制、移动、删除 | 长按操作；最近删除目录可恢复；移动前检查引用 |
| 云冲突 | 比较、选择版本、保留副本 | 同一解决流程，保护处理期间的新编辑 |
| 导出 | HTML / Markdown / PDF / bundle | 原生分享导出 |

iOS 注册的是 Markdown 文档接收入口，没有独立的文本/网页 Share Extension。
分享导入只编辑应用内副本，不能把“保存”理解为修改发送方的原文件。
两端使用同一 Apple Account 并打开 iCloud Drive。默认云端文件由系统同步；本地外部工作区不会自动上传。
iOS 会迁移旧的 Imports 副本；本机根目录新建的笔记需要手动转入云端，不能把这项迁移视为完整双向同步。

## 重复上传

本机 Xcode Accounts 登录团队后，需要 Apple Distribution 证书及私钥；首次上传已通过自动签名生成对应描述文件。
在 app 中运行 `flutter build ios --release --no-codesign --config-only`，然后从仓库根目录归档。0.1.10 起使用系统 JavaScriptCore 与 Pele，不再执行 Merman 符号替换脚本；原生 Pele 桥接通过 Native Assets 生成带 DWARF 的库和对应 dSYM。

```sh
xcodebuild \
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
- 2026-11-02 已完成真实 iPhone 与 Mac 同账户双向同步、并发编辑、两轮离线重连与 NSFileVersion 冲突解决；见 [真机验收](../../doc/ios-icloud-device-audit/2026-11-02/README.md)。模拟器目录及触屏验收见 [记录](../../doc/ios-simulator-audit/2026-11-02/README.md)。
- 首个上传有 MermanFFI.framework 缺少 dSYM 的非阻断警告；该库崩溃报告的符号解析不完整。

隐私清单依据 Apple 的 required-reason API 文档声明应用容器/用户授权文件元数据、写入容量检查及自身 UserDefaults：
https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
应用不实现自有加密；CryptoKit/SHA256 用于文件完整性，云端连接使用系统服务。

## 0.1.1 (3) · 2026-11-02

- iOS 改为与桌面共享的移动工作区，补齐目录管理、回收恢复、冲突比较与版本保留。
- 正常 iCloud 同步静默；只有明确失败或冲突显示处理入口。干净文档自动接收远端内容，未保存草稿仍受保护。
- 修复系统延迟确认导致的“解决成功却提示失败”，以及内容重新一致后的过期磁盘冲突提示。
- 使用 Release 配置与 Production iCloud 容器分发；模拟器 QA 夹具不进入真机发布构建。

## 历史：0.1.1–0.1.9 MermanFFI 符号归档

从 0.1.1 (4) 起，iPhone Release Archive 在 CocoaPods 嵌入完成后替换为同版本源码重建的 MermanFFI，并将匹配 dSYM 放入 Xcode 的符号输出目录，由 Xcode 正常归档与重新签名。Debug、模拟器及普通非 Archive 构建不受影响。

归档阶段强制核对源码版本、二进制/dSYM 的 UUID 和架构，以及 ABI 入口的真实 DWARF 源码行信息；准备阶段还比较 C 头文件和导出入口。依赖版本升级时检查会失败，必须明确更新源码锁定并重新验证。不能通过关闭 uploadSymbols 或制造空 dSYM 绕过此检查。

归档后再次验证（路径按实际归档名替换）：

```sh
python3 app/tool/verify_merman_symbols.py \
  app/build/ios/archive/Linefold.xcarchive/Products/Applications/Runner.app/Frameworks/MermanFFI.framework/MermanFFI \
  app/build/ios/archive/Linefold.xcarchive/dSYMs/MermanFFI.framework.dSYM
```

保留对应 xcarchive 和 `app/build/merman-symbols`，用于后续崩溃符号化。旧构建 (3) 的 UUID 与重建库不同，不能用新符号补充旧构建。
