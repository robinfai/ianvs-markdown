# macOS 签名与 GitHub 测试发布

应用版本位于 app/pubspec.yaml，当前版本以该文件为准。组件库已有 v0.1.0 等标签，
因此应用使用 linefold-v<版本>。工作流为 .github/workflows/release.yml。

## 1. 创建与导出证书

在 Xcode → Settings → Accounts 添加已加入 Apple Developer Program 的账号。
选中团队 → Manage Certificates → + → Developer ID Application。
也可按 Apple 官方指南通过 Developer 网站申请：
https://developer.apple.com/help/account/certificates/create-developer-id-certificates

打开“钥匙串访问”→ 登录 → 我的证书，找到 Developer ID Application: 名称 (TEAMID)。
确认展开后有私钥，导出为 .p12，并设置强导出密码。证书与私钥不要放入仓库。
只导出 .cer 不够；Apple Development / Apple Distribution 不能替代 Developer ID Application。
使用 security find-identity -v -p codesigning 可查看证书 SHA-1 指纹。

## 2. 准备 Apple 公证凭据

登录 https://account.apple.com → 登录与安全 → App 专用密码，生成供 Linefold CI 使用的密码。
需启用双重认证。Team ID 可在 https://developer.apple.com/account 的会员信息中查看。
官方说明：https://support.apple.com/en-us/102654

## 3. 配置 GitHub Actions secrets

https://github.com/robinfai/ianvs-markdown/settings/secrets/actions

| 名称 | 值 |
| --- | --- |
| APPLE_CERTIFICATE_P12_BASE64 | .p12 文件的 base64 编码 |
| APPLE_CERTIFICATE_PASSWORD | 导出 .p12 时设置的密码 |
| APPLE_SIGNING_IDENTITY | Developer ID Application 证书的 SHA-1 指纹 |
| APPLE_ID | 开发者 Apple Account 登录邮箱 |
| APPLE_TEAM_ID | 10 位 Team ID |
| APPLE_APP_SPECIFIC_PASSWORD | Apple 专用密码，不是账号登录密码 |
| APPLE_MACOS_PROVISIONING_PROFILE_BASE64 | Linefold Developer ID iCloud 的 .provisionprofile 文件 base64 |

在本机将 base64 编码复制到剪贴板（按实际文件路径替换）：

```sh
base64 -i "$HOME/Desktop/DeveloperID.p12" | pbcopy
```

密码仅填写到 GitHub Secret，不要写入聊天、提交或日志。Runner 使用随机密码的临时钥匙串，
任务结束清理证书。发布构建默认启用专属 iCloud Documents 容器 `iCloud.work.ianvs.linefold`。
在 Developer Portal 为 `work.ianvs.linefold` 创建 Developer ID 描述文件，选择 CI 的同一证书，
下载并配置上述 profile secret。签名脚本校验团队、App ID、容器、生产环境和有效期，
将描述文件嵌入应用并签入对应权限；缺少授权时发布失败，不退回本地模式。
普通本地构建仍可不配置开发者账号。

## 4. 发布

先将工作流、签名脚本和发布说明提交并推送到 main，再对该提交创建标签：

```sh
git tag -a linefold-v0.1.1 -m 'Linefold 0.1.1 test release'
git push origin linefold-v0.1.1
```

CI 检查版本和凭据 → 测试 → Release 构建 → 嵌套代码逐层签名 → notarytool 公证 →
staple → Gatekeeper 检查 → ZIP 和 SHA256 → GitHub Pre-release。
目前按 macos-15 runner 原生架构构建，产物文件名明确包含 arm64 或 x86_64。
未实现双架构矩阵。任何前置失败都不会发布未签名替代品。

首次公证可能超过等待时间；查看 Actions 的 notarization-result artifact 中的 submission id。
需要时使用 notarytool log 获取 Apple 的具体错误。修复后可在 Actions 选择原标签重新运行。
如果同名 Release 已存在，流程会拒绝覆盖；不要重写已经发布的标签。

完整签名、公证和下载运行验证需要真实凭据与首次 CI 执行；静态检查不能替代这些验收。
