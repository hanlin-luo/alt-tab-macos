# FORK_NOTES — hanlin-luo/alt-tab-macos 维护手册

这是 `lwouis/alt-tab-macos` 的个人 fork，唯一目的：**跟随官方更新，同时保持 Pro 功能本地解锁**。

## 仓库结构

- `origin` → https://github.com/hanlin-luo/alt-tab-macos （本 fork）
- `upstream` → https://github.com/lwouis/alt-tab-macos （官方仓库）
- 分支策略：**直接在 `master` 上维护解锁补丁**（不另开分支），让克隆下来直接就是解锁版

## 解锁补丁（核心）

文件：`src/pro/license/LicenseManager.swift`，函数 `computeState()` 顶部：

```swift
let forkUnlockPro = true // [FORK-PATCH] unconditional Pro unlock
if forkUnlockPro { return .pro }
```

效果：许可证状态机永远返回 `.pro` → `isProAvailable = true`、`isProLocked = false`
→ 搜索 / 三种切换器样式 / 自动调整大小 / 9 组快捷键全部可用；
→ 不再出现试用倒计时、Day X 升级提示；不再发起许可证网络验证。

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

**前置：签名与版本号。** 上游 release.xcconfig 硬编码了原作者的证书，本机用
`config/local.xcconfig`（已被 .gitignore，不会进仓库）覆盖：

```
CODE_SIGN_IDENTITY = Local Self-Signed        // scripts/codesign/setup_local.sh 生成的自签名证书
OTHER_CODE_SIGN_FLAGS = --deep --timestamp=none
ENABLE_HARDENED_RUNTIME = NO
CURRENT_PROJECT_VERSION = 11.4.3              // 与上游最新 tag 保持一致
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

## 安装自编译版注意事项

1. 自签名版本过不了 Gatekeeper：首次运行**右键 → 打开**。
2. 签名身份与官方版不同 → 系统设置里要重新授权「辅助功能」和「屏幕录制」。
   （TCC 权限按签名身份绑定，重新编译同证书不用重复授权。）
3. 无 Sparkle 自动更新——更新靠 `sync-upstream.sh` + 重新编译。
4. 与官方版**不要同时运行**（bundle id 相同，会互相冲突）。

## 法律说明

上游为 GPLv3。修改、编译、公开 fork 均合法，前提是本 fork 继续保持 GPLv3
且源码公开（当前状态即合规）。自用随意；若再分发二进制，需附带源码。
