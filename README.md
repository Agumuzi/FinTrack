# FinTrack

FinTrack 是使用 SwiftUI 和 SwiftData 构建的原生 macOS 个人财务管理应用，当前正式版本为 **v1.0**。

支持收支记账、账户与资产、预算和财务目标、定期存款、贷款与周期记账、财务统计、多币种与汇率查询、菜单栏快速操作，以及 CSV 导入导出和本地完整备份恢复。

## 下载与安装

从 [GitHub Releases](https://github.com/Agumuzi/FinTrack/releases/tag/v1.0) 下载 `FinTrack-v1.0-macOS.zip`，按同页 SHA256 校验，解压后将 `FinTrack.app` 拖入“应用程序”。

- 系统要求：macOS 15.0 或更高版本。
- 安装包包含 Apple Silicon 和 Intel 架构；实际运行验证在 Apple Silicon 上完成，Intel 实机兼容性尚未验证。
- 当前使用 Ad-hoc 签名，未提供 Apple Developer ID 签名及 Apple 公证。从网络下载后，macOS 可能要求在“隐私与安全性”中允许打开；不要关闭系统整体安全保护。
- 覆盖升级前退出旧版并备份账本。大量录入前，先以少量数据检查保存、退出重开、备份和恢复。

## 从源码构建

需要 macOS、Xcode 及 XcodeGen。此版本使用 Xcode 27.1 构建。

```sh
xcodegen generate --spec MacApp/project.yml --project MacApp
xcodebuild build \
  -project MacApp/FinTrackMac.xcodeproj \
  -scheme FinTrackMac -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=YES
```

应用生成在 `.build/Build/Products/Release/FinTrackMac.app`，可复制并命名为 `FinTrack.app`。生成的 Xcode 工程不纳入源码。

`MacApp/Sources` 为 macOS 应用，`MacApp/Resources` 为资源；`FinTrack` 中的模型及共享业务文件由工程直接引用。应用 Bundle Identifier 为 `dev.agumuzi.fintrack.macos`。

## 数据与限制

账本独立保存在用户的 `~/Library/Application Support/FinTrackMac/FinTrack.sqlite`，不位于源码目录。请通过应用提供的完整备份功能保存账本；备份包含私人财务信息，应妥善保管。API 密钥存储在本机钥匙串，不随备份迁移。

汇率依赖外部来源，其报价日期、币种覆盖和可用性受来源限制。应用内在线升级需要另行配置可信的签名更新源；当前通过 Releases 手动安装更新。

Intel 实机、完整 VoiceOver 和长期真实财务使用尚未验证。请先以少量数据检查保存、备份和恢复，再逐步投入日常使用。

本仓库公开提供源代码，暂未授予开源许可证；公开可见不代表已授权自由再分发。第三方图标及素材的来源记录随相应资源保留。
