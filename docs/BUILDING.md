# 从源码构建 macOS 应用

## 环境

- macOS；应用最低运行版本为 macOS 15.0。
- Xcode 27.1 及命令行工具（当前验证环境）。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)，可通过 Homebrew 安装：`brew install xcodegen`。

应用使用 Apple 系统 SDK，没有需要下载的第三方运行时包。工程由 `Project/project.yml` 生成，生成的 `.xcodeproj` 不提交到仓库。

## Release 编译

```sh
git clone https://github.com/Agumuzi/FinTrack.git
cd FinTrack
./scripts/build-macos.sh Release
```

输出：`.build/app/Build/Products/Release/FinTrack.app`。默认同时构建 arm64 和 x86_64，使用 Ad-hoc 签名；本地编译不等于完成 Developer ID 签名或 Apple 公证。脚本只编译，不启动应用。

如需指定构建目录，可设置 `FINTRACK_DERIVED_DATA_PATH`。当前源码版本配置为 `1.0` / Build `1`；下载的正式安装包以 Release 页面对应的 Tag 为准。

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
