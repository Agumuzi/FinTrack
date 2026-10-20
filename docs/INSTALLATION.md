# 安装与更新

## 下载和校验

从 [v1.1 Release](https://github.com/Agumuzi/FinTrack/releases/tag/v1.1) 下载 `FinTrack-v1.1-macOS.zip` 和 `SHA256.txt`。需要 macOS 15.0 或更高版本；安装包包含 Apple Silicon 和 Intel 架构。

在下载目录检查：

```sh
shasum -a 256 -c SHA256.txt
```

确认结果为 `OK`，再解压 ZIP，将 `FinTrack.app` 拖入“应用程序”。

## 首次打开

当前包采用 Ad-hoc 签名，没有 Apple Developer ID 签名，也未经过 Apple 公证。首次打开网络下载的应用时，macOS 可能阻止运行。确认下载来源与校验值后，可按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在尝试打开后进入“系统设置 → 隐私与安全性”，为该应用选择“仍要打开”。不同系统版本或管理策略下的提示可能不同。

不需要关闭整个系统的安全保护。若系统报告应用损坏或恶意内容，应停止并核对下载来源。

## 开始使用

应用不预装示例账本。先录入少量数据，退出后重新打开，核对金额与记录；创建一次原生完整备份，妥善保存。大量录入前，应在独立副本中验证恢复能力。

网站截图中的记录均为示例，不随应用交付。

## 安全更新

1. 在旧版中创建完整备份，妥善保存，再完全退出 FinTrack。
2. 从 [GitHub Releases](https://github.com/Agumuzi/FinTrack/releases) 下载目标版本的 ZIP 和同版 `SHA256.txt`，核验后解压。
3. 将新的 `FinTrack.app` 拖入“应用程序”，选择替换旧应用，再打开并核对版本和已有账目。

账本独立保存在本机，替换 `.app` 会沿用已有账本和配置。不要手动删除账本目录或移动运行中的 SQLite 文件。钥匙串 API Key 不随原生账本备份导出。

当前通过 Releases 手动更新。在线更新需要另行配置可信的签名源；没有配置时，不应把在线更新视为可用的分发途径。

Intel 实机、macOS 15 实机、完整 VoiceOver 及长期真实财务场景尚未完成验证。
