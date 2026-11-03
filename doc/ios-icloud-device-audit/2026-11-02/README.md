# 真实 iCloud 跨端验收 · 2026-11-02

## 环境

Mac 当前代码的 Debug 开发签名构建与 iPhone 17 / iOS 27.0.1 的 Release 开发签名构建，使用同一个 `iCloud.work.ianvs.linefold` 容器。此次未启用模拟器 QA 样例。Xcode 为现有开发团队生成了两端描述文件，应用均实际进入“iCloud · Linefold”工作区。

测试仅操作本次创建的 `Untitled-28.mdCloud-Acceptance-20261102-1914.md` 及其副本。文件名包含自动化输入时遗留的草稿名前缀，不影响内容验收。通过 Mac 原生 UI、iPhone 镜像操作，另以 Mac 已接收文件逐字核对。

## 已实际验证

1. Mac 创建并保存，iPhone 列表出现文档，打开收到 `BASE-MAC-1914`。[截图](01-iphone-received-base.png)
2. **发现并修复**：无本地修改的 iPhone 文档收到新版本时，旧代码也显示“changed on disk”。现改为云工作区中的干净文档自动更新，读取完成后再次检查 dirty 状态；未保存编辑、删除/读取失败及已有冲突仍受保护。重新构建安装后，Mac 保存 `MAC-CLEAN-1918`，iPhone 自动显示该内容，无冲突条或常规同步状态。[截图](02-iphone-silent-update.png)
3. iPhone 输入 `IOS-UNSAVED-1919` 不保存；Mac 将同一文件保存为 `MAC-CONCURRENT-1919`。远端内容到达后，iPhone 保留草稿并显示需要处理的磁盘冲突。[截图](03-concurrent-draft-protected.png)
4. 手机点击 Resolve & Save → Compare Changes，看到实际两端内容差异；返回选择 Keep Both。[差异截图](04-real-concurrent-diff.png)
5. Mac 收到手机生成的 `… local copy.md`，实际打开显示 `IOS-UNSAVED-1919`；原文件仍为 `MAC-CONCURRENT-1919`。两份内容均未丢失。[Mac 截图](05-mac-received-ios-copy.png)、[落盘核对](concurrent-content.json)

6. 第一轮真实离线：手机开启飞行模式并关闭 Wi-Fi，通过 USB 操作保存；Mac 同时保存不同内容。手机保持本地已保存，实际 provider 上传失败才出现可查看的错误。[离线截图](06-iphone-offline-saved.png)、[失败详情](07-offline-provider-error.png)。
7. 恢复联网后，两端均收到系统未解决版本（NSFileVersion），手机比较界面包含两端实际内容。选择云端版本后，Mac 收到所选内容和保留手机内容的 conflict 副本。[真实冲突](08-native-cloud-conflict.png)、[版本差异](09-real-offline-version-diff.png)、[第一次落盘核对](offline-resolved-content.json)。
8. **发现并修复**：原生标记版本已解决后，立即读取系统版本列表仍可能返回旧版本；旧代码因此把成功的操作报为失败。现在内容与副本成功落盘后，将该状态返回为等待 iCloud 确认，避免误报和引导用户重复处理。保存失败仍返回错误。
9. 重建两端后，再次让手机完全离线保存 `MAC-WHILsecondE-IOS-OFFLINE-1924`，Mac 保存 `MAC-SECOND-OFFLINE-1932`。恢复网络后再次产生真实系统冲突，在 Mac 打开版本比较，在 iPhone 选择云端版本。[第二轮离线](10-second-offline-saved.png)、[第二轮差异](11-second-real-version-diff.png)。手机显示“内容和 1 份副本已保存；等待 iCloud 确认”，随后两端云冲突标记自动消失，没有再次出现“处理未完成”。[处理反馈](12-resolution-saved-awaiting-cloud.png)、[手机冲突消除](13-phone-conflict-cleared.png)。
10. **收尾修复**：Mac 在云冲突解除后可能保留已有磁盘冲突条。云工作区重新成功读取到与本地保存基线一致的内容且没有未保存编辑时，现清除过期提示；未保存编辑、读取失败或真正不同的内容仍保留保护。补充回归覆盖暂时不可读后恢复及 dirty 状态保护。最终 Mac 构建重启后状态正常；本条没有额外制造第三轮原生冲突，收尾逻辑由定向回归验证。
11. iPhone 正常保存 `MAC-doneSECOND-OFFLINE-1932`，Mac 已打开文档自动更新为完全相同内容，两端无常规同步进度、弹窗或冲突条。[手机](14-phone-normal-save.png)、[Mac 自动更新](15-mac-silent-reverse-update.png)。
12. 最终从 Mac iCloud 容器逐字核对：原文、当前文档、两轮不同的手机离线内容均在对应文件中。[最终内容](final-cloud-content.json)。手机已恢复 Wi-Fi 与蜂窝网络。

## 验证范围与构建

- 真实同账户 iPhone 17 / iOS 27.0.1 与 Mac，实际 iCloud 容器；未用注入的冲突夹具替代以上实际操作。覆盖正常双向更新、未保存草稿与远端并发、两次离线分别保存后重连、系统冲突比较及选择版本、保留副本和跨端收敛。
- 手机输入受到当前中文输入法影响，标记串中保留了实际插入位置；落盘断言使用真实内容，并非假设输入目标已执行。
- 31 项 Flutter 定向回归通过；Swift 原生管理回归通过，包含 iCloud 延迟确认的内容安全测试；flutter analyze 无问题。两端开发签名构建通过。构建不是以上实测的替代证据。
- Mac 运行仓库下 Debug 开发构建，没有覆盖 `/Applications/Linefold.app`。手机实测版包含正常更新和原生解决结果修复；最后的过期磁盘提示清理已在 Mac 实测最终构建和共享 Dart 回归覆盖。
- 结论限于本次设备、账户和场景；未宣称验证所有 iCloud 服务故障、设备系统版本或长时间离线组合。本次不修改已有用户笔记，也未删除验收副本。
