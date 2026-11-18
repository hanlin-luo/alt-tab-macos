# FORK_NOTES — hanlin-luo/alt-tab-macos 维护手册

这是 `lwouis/alt-tab-macos` 的个人 fork，唯一目的：**跟随官方更新，同时保持 Pro 功能本地解锁**。

## 仓库结构

- `origin` → https://github.com/hanlin-luo/alt-tab-macos （本 fork）
- `upstream` → https://github.com/lwouis/alt-tab-macos （官方仓库）
- 分支策略：**直接在 `master` 上维护解锁补丁**（不另开分支），让克隆下来直接就是解锁版

## 解锁补丁（核心）

文件：`src/pro/license/LicenseManager.swift`，函数 `computeState()`：

```swift
// [FORK-PATCH] hanlin-luo fork: always report an active Pro license so every
// Pro feature (search, styles, auto-size, extra shortcuts) is unlocked locally.
func computeState() -> LicenseState {
    .pro // [FORK-PATCH] unconditional Pro unlock
}
```

注意：上游原本的 keychain / 试用 / 远端校验逻辑**已被整段删除**（不是加判断早退），
因为删掉之后的分支会变成 unreachable code，Swift 直接编译报错。合并上游时，
`computeState()` 必须保持只有 `return .pro` 一行。

效果：许可证状态机永远返回 `.pro` → `isProAvailable = true`、`isProLocked = false`
→ 搜索 / 三种切换器样式 / 自动调整大小 / 9 组快捷键全部可用；
→ 不再出现试用倒计时、Day X 升级提示；不再发起许可证网络验证。

运行时自检：app 会把许可证档位写成 `license=pro` 的 cookie（`syncLicenseCookie`），
落在 `~/Library/HTTPStorages/com.lwouis.alt-tab-macos.binarycookies` 里。

所有补丁代码都带 `[FORK-PATCH]` 注释，合并上游时用 `grep -rn "FORK-PATCH" src/` 确认补丁还在。

## 日常维护

```bash
bash sync-upstream.sh            # 拉上游 → 合并 → 校验补丁 → 推送到 fork
bash sync-upstream.sh --no-push  # 只在本地合并，不推送
```

脚本会自动：补齐完整历史（首次）→ fetch 双 remote → merge upstream/master →
**校验补丁标记仍然存在** → push。若上游改动了补丁附近代码导致冲突，脚本会停下并给出修复指引。

## 本地编译

```bash
# 编译 Release（产物在 DerivedData/Build/Products/Release/AltTab.app）
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData

# 或一键脚本（会写 build.log 和 .build-done / .build-failed 标记）
bash build-fork.sh
```

脚本已内置 `-IDEPackageSupportDisableManifestSandbox=1
-IDEPackageSupportDisablePluginExecutionSandbox=1`：受限环境（Agent 沙箱/容器）里
SwiftPM 的 manifest 编译沙箱无法嵌套，会报 `sandbox-exec: sandbox_apply: Operation
not permitted`，这两个 flag 是唯一有效解法（`-disableAutomaticPackageResolution`、
`-skipPackageUpdates` 都无效）。

**前置：签名与版本号。** 上游 release.xcconfig 硬编码了原作者的证书，本机用
`config/local.xcconfig`（已被 .gitignore，不会进仓库）覆盖：

```
CODE_SIGN_IDENTITY = Local Self-Signed        // scripts/codesign/setup_local.sh 生成的自签名证书
OTHER_CODE_SIGN_FLAGS = --deep --timestamp=none
ENABLE_HARDENED_RUNTIME = NO
CURRENT_PROJECT_VERSION = 11.10.2             // 与上游最新 release 保持一致
```

两个关键教训（都是实测踩出来的）：

1. **不要用真实 Developer ID 证书签本地版**：未公证的 Developer ID 应用会被
   LaunchServices **静默拒绝**（双击/右键打开都无响应、无弹窗）。自签名证书无此问题，
   且同一证书重编译后 TCC 权限（辅助功能/屏幕录制）不用重授。
2. **必须注入版本号**：Info.plist 里 `CFBundleVersion` 来自 `$(CURRENT_PROJECT_VERSION)`，
   上游靠 CI 注入；缺了它编译产物不含版本键，`App.swift` 强制解包直接 SIGTRAP 闪退。
   `build-fork.sh` 会自动取最新 git tag 注入（`xcodebuild CURRENT_PROJECT_VERSION=x.y.z`），
   无需手动维护。

要求：Xcode（已在用 26.6）、Swift 5.8 语法、部署目标 macOS 10.13。

## 没有 Xcode 时的编译（Command Line Tools 即可）

有些机器只装了 Command Line Tools，没装完整 Xcode。这时 `xcodebuild` 根本跑不起来
（`xcode-select: error: tool 'xcodebuild' requires Xcode`），而 `ibtool` / `actool`
也只有 Xcode 才带。本 fork 为此准备了一条纯 SwiftPM 的构建路径：

```bash
bash scripts/codesign/setup_local.sh   # 生成自签名证书 + 专用签名钥匙串（只需跑一次）
bash scripts/build_local.sh            # 编译 → 组装 .app → 签名 → 安装到 /Applications
bash scripts/build_local.sh --no-install   # 只出产物，不安装
```

它做的事：

- `Package.swift`（由 `scripts/generate_package_manifest.py` 生成）描述了与 Xcode 工程
  **同一个 app target**：同样的 232 个 Swift 文件 + 2 个 Objective-C 文件，同样的排除项
  （单元测试、`*Specs.md`）。依赖仍是 `vendor/` 下那三个本地 SPM 包。
- `scripts/build_local.sh` 负责 Xcode 工程的那些 build phase 干的事：拷资源、生成
  `Info.plist`、嵌 `Sparkle.framework` / `CrashReporter.framework`、跑仓库自带的
  `scripts/copy_sparkle_helpers.sh`、签名。
- `scripts/generate_info_plist.py` 直接读 `config/base.xcconfig` + `config/release.xcconfig`
  + `config/local.xcconfig` 做变量替换，和 Xcode 的 Info.plist 处理结果一致。

两处绕不开 Xcode 工具的地方：

1. **Sparkle 的 3 个 xib**：SPM 用 `ibtool` 编译 xib，没有 Xcode 就编不了。改成用官方
   release tarball 里**已编译好的 .nib**（`vendor/Sparkle/Sources/Sparkle/*.nib`），
   `vendor/scripts/update_sparkle.sh` 里同步改了，更新 vendor 时不会退回旧状态。
2. **ShortcutRecorder 的 `Images.xcassets`**：SPM 用 `actool` 编译资源目录，同样没有
   Xcode 就编不了。分两部分处理：
   - 图片：把 imageset 里的 PNG 平铺进 `ShortcutRecorder_ShortcutRecorder.bundle/Contents/Resources/`——
     `-[NSBundle imageForResource:]` 会自动把 `<name>.png` 和 `<name>@2x.png` 配成一张
     多分辨率 NSImage，ShortcutRecorder 的 `SRImage()` 正是这么找图的，效果一致。
   - **样式描述（`sr-mojave-info` / `sr-yosemite-info`）是 data asset，不是图片**：
     `NSDataAsset` 只认**已编译**的资源目录，平铺的 JSON 它看不见。而
     `SRRecorderControlStyle` 拿不到它就会
     `raise NSInternalInconsistencyException("Missing sr-mojave-info")`——
     macOS 26 起 AppKit 把未捕获的 NSException 变成 SIGTRAP，**一点 Settings 就必崩**
     （Settings 的 Controls 标签页会建 ShortcutRecorder 控件）。所以给
     `SRRecorderControlStyle.m` 打了个补丁：拿不到编译资源时回退读 dataset 里的
     `info.json`（也就是编译后本该存的那几个字节），见
     `vendor/scripts/update_shortcut_recorder.sh` 里的 `patch_sr_style_info_fallback`。

签名有一个坑（实测卡了很久）：**codesign 用钥匙串里的私钥签名时，如果 key 没有设
partition list，会永远卡在钥匙串授权弹窗上**（securityd 日志：
`ACL partition mismatch: client apple: ACL ("apple-tool:")` → `displaying keychain prompt`）。
非交互脚本等不到那个弹窗的答案。`scripts/codesign/setup_local.sh` 因此把证书导入一个
**专用钥匙串**（`alttab-signing.keychain-db`），并执行：

```bash
security set-key-partition-list -S apple-tool:,apple: -s -k <钥匙串密码> <钥匙串>
```

这一步需要钥匙串密码，所以不能放在登录钥匙串里（拿不到它的密码）。

钥匙串密码存在 `scripts/codesign/alttab-signing.pass`（已 gitignore），**和 PKCS#12 容器的密码
是同一个**，所以容器随时能重新导入。`scripts/build_local.sh` 每次签名前都会用这个密码解锁
钥匙串，正常情况下**不会弹窗**。

两个别再踩的坑：

- `security set-keychain-settings` **不要加 `-t`（自动锁定超时）也不要加 `-l`（睡眠时锁定）**：
  加了之后钥匙串会自己锁上，下一次 codesign 就弹出「请输入钥匙串密码」的对话框——
  登录密码没用（这是独立钥匙串），非交互脚本就永远卡住。`setup_local.sh` 现在不设这两个参数。
- `security add-trusted-cert` 对**已经信任过的**证书再执行一次，会要求用户授权改动信任设置
  （又是一个弹窗）。`setup_local.sh` 会先查 `security dump-trust-settings`，已信任就跳过。

## 安装自编译版注意事项

1. 自签名版本过不了 Gatekeeper：首次运行**右键 → 打开**。
2. 签名身份与官方版不同 → 系统设置里要重新授权「辅助功能」和「屏幕录制」。
   （TCC 权限按签名身份绑定，重新编译同证书不用重复授权。）
3. 无 Sparkle 自动更新——更新靠 `sync-upstream.sh` + 重新编译。
4. 与官方版**不要同时运行**（bundle id 相同，会互相冲突）。

## 法律说明

上游为 GPLv3。修改、编译、公开 fork 均合法，前提是本 fork 继续保持 GPLv3
且源码公开（当前状态即合规）。自用随意；若再分发二进制，需附带源码。
