# 从源码构建 macOS 应用

## 环境

- macOS；应用最低运行版本为 macOS 15.0。
- Xcode 27 系列及命令行工具；当前本地验证环境为 Xcode 27.1，CI 使用 GitHub 的 Xcode 27 镜像。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)，可通过 Homebrew 安装：`brew install xcodegen`。

应用使用 Apple 系统 SDK，没有需要下载的第三方运行时包。工程由 `Project/project.yml` 生成，生成的 `.xcodeproj` 不提交到仓库。

Xcode 和本项目的 Ad-hoc 构建不要求付费 Apple Developer 会员。编译由脚本调用 Xcode 命令行工具完成，无需打开 Xcode 窗口；发布包通过 GitHub Releases 提供 ZIP，由用户手动下载替换旧应用。

## Release 编译

```sh
git clone https://github.com/Agumuzi/FinTrack.git
cd FinTrack
./scripts/build-macos.sh Release
```

输出：`.build/app/Build/Products/Release/FinTrack.app`。默认同时构建 arm64 和 x86_64，使用 Ad-hoc 签名；本地编译不等于完成 Developer ID 签名或 Apple 公证。脚本只编译，不启动应用。

如需指定构建目录，可设置 `FINTRACK_DERIVED_DATA_PATH`。源码版本配置见 `Project/project.yml` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`；已发布安装包以 Release 页面对应的 Tag 为准。

## 在 Xcode 中查看

```sh
xcodegen generate --spec Project/project.yml --project Project
open Project/FinTrack.xcodeproj
```

选择 `FinTrack` scheme。默认 Debug Run 使用内存中的独立开发账本和模拟汇率，不读取正式账本；此账本在退出后不保留。Release 应用正常启动时使用正式本地存储，因此请先做好备份，不要对日常使用的真实账本进行开发试验。

Bundle Identifier 保持为 `dev.agumuzi.fintrack.macos`。不要随意修改模型或存储路径；这些都可能影响既有账本的兼容性。

## 产品网站

网站源码位于 `website/`，无需依赖安装。预览可使用任意静态服务器，例如：

```sh
python3 -m http.server 8000 --directory website
```

访问 `http://localhost:8000/`。`scripts/check-site.py` 检查本地资源和锚点；GitHub Actions 在合并后部署至 [GitHub Pages](https://agumuzi.github.io/FinTrack/)。网站不依赖前端框架、第三方字体或分析服务。


## 独立密钥组件

`Resources/FinTrackKeychainHelper` 是具有独立组件版本的 Universal 签名程序，源码位于 `Sources/Core/Security/KeychainHelper/`，不参与主应用重新编译。普通应用发布复用其原始字节，避免旧版钥匙串按程序指纹重新要求授权。`scripts/verify-keychain-helper.py` 检查源码、双架构签名与固定摘要；构建和签名不得改写该组件。组件安全更新需要独立评估授权迁移，不能随应用版本自动重签。

主应用和组件相互验证官方固定身份；组件只接受父应用通过私有管道发送的请求，API Key 不进入命令行、日志或临时文件。自行发布的 fork 必须使用自己的身份构建并配置组件，不能使用官方组件访问官方应用的密钥。正式账本、Bundle ID 和 API Key 服务标识保持不变。

构建目录中的产物及明确命名的验证副本需要显式隔离参数；缺少参数时会停止打开账本，避免意外访问日常数据。正式使用请将已确认的应用复制到 Applications。
