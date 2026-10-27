# FinTrack 文档导航

本目录既面向希望了解 FinTrack 的使用者，也面向进行代码审查与维护的开发者或 AI 编程助手。先阅读与任务直接相关的文档，再进入对应源码模块，避免在整个仓库中盲目查找。

## 用户与安全

| 文档 | 内容 |
| --- | --- |
| [README](../README.md) | 产品功能、下载入口与当前版本 |
| [安装指南](INSTALLATION.md) | 下载、校验、首次启动与更新 |
| [数据和隐私](PRIVACY.md) | 本地账本、备份、汇率服务与敏感数据 |
| [截图说明](SCREENSHOTS.md) | 官方界面素材与示例数据 |
| [安全政策](../SECURITY.md) | 漏洞私密报告 |
| [社区行为准则](../CODE_OF_CONDUCT.md) | 贡献与讨论规范 |

## 开发与发布

| 文档 | 内容 |
| --- | --- |
| [源码架构](ARCHITECTURE.md) | SwiftUI / SwiftData、目录职责与持久化模型 |
| [源码构建](BUILDING.md) | XcodeGen、Universal 构建、构建输出与密钥组件约束 |
| [更新记录](../CHANGELOG.md) | 版本历史 |
| [贡献指南](../CONTRIBUTING.md) | Bug 反馈、PR 规范与数据保护 |
| [第三方素材](THIRD_PARTY_NOTICES.md) | 素材与组件许可 |

## 常见任务的阅读顺序

- **记账、账户、报表、预算、存贷款计算**：`ARCHITECTURE.md` → `Sources/Shared/` → `Sources/Core/Finance/` 或 `Sources/Features/` 的对应模块。
- **SwiftData 模型、数据迁移或备份**：`PRIVACY.md` → `ARCHITECTURE.md` → `Sources/Shared/Models/` → `Sources/Core/Persistence/`。不得以删除真实用户账本作为默认修复。
- **汇率、菜单栏与快捷换算**：`ARCHITECTURE.md` → `Sources/Core/Exchange/` → `Sources/Features/Exchange/`。
- **UI、多语言和无障碍**：`Sources/Components/`、`Sources/Features/`、`Resources/Localizable.xcstrings`。同步检查浅色/深色、布局与键盘行为。
- **应用打包与安装**：`BUILDING.md` → `INSTALLATION.md` → `scripts/build-macos.sh` → `.github/workflows/build.yml`。
- **官网与下载页面**：`website/` → `scripts/check-site.py` → `.github/workflows/pages.yml`。

## 自动化验证的边界

- `.github/workflows/build.yml` 在 GitHub macOS 运行器上验证应用构建、签名、资源与稳定的密钥辅助程序。
- `tests/FinanceSmoke.swift` 是独立的轻量 **金融计算冒烟测试**，编译时直接引用两个真实计算源文件，不依赖真实账本，也不会启动 App。该脚本只覆盖财务金额精度和存款利息结算的部分边界情形。
- `pages.yml` 验证官网 JavaScript、本地化切换和静态页面资源。
- 上述验证**不等于**完整 SwiftData、UI 或真实环境端到端测试。计划增加完整测试套件时，应另建专用测试目标，并使用虚构/隔离的账本。

> **重要边界：** `Resources/FinTrackKeychainHelper` 是固定身份的独立签名程序，不能因为普通应用重构而重新签名。详情见 [BUILDING.md](BUILDING.md)。正式用户的数据、签名材料、真实 API 密钥和本地缓存不得提交到 GitHub。
