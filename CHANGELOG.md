# 更新记录

此处记录已发布的应用版本。安装包与校验文件见 [GitHub Releases](https://github.com/Agumuzi/FinTrack/releases)。

## v1.1 — 2026-10-20

- CSV 导入时同步登记收支分类；升级后进入分类管理会补齐旧导入账目的分类，并可重命名已有引用。
- 全新安装以空白账本、空白分类和空白关注货币对开始；升级保留已有账本、分类与汇率设置。
- 内置官方 Ed25519 签名更新源；从 v1.1 起可在“关于 FinTrack”中检查、下载并校验后续版本，确认后安装。
- 保持原有账本位置和应用标识，无需重新导入已有数据。更新前建议创建一次完整备份。

系统要求：macOS 15.0+；Universal（Apple Silicon / Intel）。安装包为 Ad-hoc 签名，未经 Apple 公证。

[下载与版本说明](https://github.com/Agumuzi/FinTrack/releases/tag/v1.1) · [安装指南](docs/INSTALLATION.md)

## v1.0 — 2026-10-19

首个正式 macOS 版本。

- 收支记账、账户与资产、预算与财务目标。
- 存款、贷款与周期记账管理。
- 分类统计、趋势及期间比较。
- 多币种账目、汇率查询与换算、记账汇率快照。
- 菜单栏快速操作、浅色与深色外观。
- 原生完整备份恢复，以及四类 CSV 导入导出。

系统要求：macOS 15.0+；Universal（Apple Silicon / Intel）。当前安装包为 Ad-hoc 签名，未经 Apple 公证。Intel 实机、完整 VoiceOver 及长期真实财务使用尚未验证。

[下载与版本说明](https://github.com/Agumuzi/FinTrack/releases/tag/v1.0) · [安装指南](docs/INSTALLATION.md)
