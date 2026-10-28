# 第三方组件、图标与素材说明

本说明记录 FinTrack 随附资源的来源及已核对的使用范围，不替代各权利人的许可条款，也不为第三方素材授予额外权利。核对日期：2026-10-23。

## 项目许可证

本仓库当前的原创软件源代码采用 [PolyForm Noncommercial 1.0.0](../LICENSE)，在其许可范围内允许非商业使用、修改及分发；随应用提供的对应许可副本位于 `Resources/Legal/LICENSE.txt`。原创 Logo、应用图标、宣传图及软件截图另受[品牌素材声明](../ASSETS-LICENSE.md)约束，不因源码许可而获得独立复用授权。此前按 MIT 发布的版本保留已授予的许可，历史文本存于[旧版 MIT 许可证](LEGACY_MIT_LICENSE.md)。第三方素材和 Apple 平台组件仍遵循各自条款，本项目不对第三方商标、字体或系统图库重新授权。

## 平台组件与代码依赖

当前应用构建使用 Apple 提供的 SwiftUI、SwiftData、AppKit、Foundation、Charts、Combine、CryptoKit、Security 等系统 SDK。应用工程未声明 Swift Package Manager、CocoaPods 或 Carthage 运行时依赖，未发现随应用源码附带的独立第三方代码包及其许可证。

系统 SDK 由 Apple 的适用协议管理，本说明不对其重新授权。构建工具 Xcode 与 XcodeGen 不作为应用运行时组件打包；使用工具时仍需遵守各自条款。

## 系统界面图标与字体

应用通过系统 API 使用 SF Symbols 和系统字体。没有把 Apple 字体或 SF Symbols 独立图库作为应用资源分发。Apple 对部分符号的用途、修改及商标使用设有限制；例如，SF Symbols 不得直接用于应用图标、标志或其他商标用途。参见 [Apple SF Symbols 指南](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)及 [Apple SF Symbols 页面](https://developer.apple.com/sf-symbols/)。

产品网站使用系统字体栈；实际应用截图中出现系统界面图标，不表示可将这些图标或字体单独提取为网站素材。

## 货币选择中的国旗及地区旗帜

- 文件：`Resources/Flags/flag-*.png`。
- 来源：[Flagcdn](https://flagcdn.com/) / [Flagpedia](https://flagpedia.net/)。
- 范围：美国、俄罗斯、中国、欧盟、英国、日本、瑞士和香港的随附旗帜图片。

Flagcdn 说明图片以 Wikimedia Commons 的矢量文件为基础；[Flagpedia 使用条款的知识产权部分](https://flagpedia.net/terms)明确声明其提供的旗帜图片属于公有领域，可以自由使用。这一说明适用于旗帜图片，不适用于该站点的其他文字、设计或代码。

原始下载地址保存在 `Resources/Flags/sources.json`。这些图像用于货币或地区识别，不表示官方合作或背书。

## FinTrack 图标与软件截图

FinTrack 自行制作的应用图标与原创品牌图形不按软件代码许可证授权，除获单独许可或法律允许外，不得提取用于其他项目。界面实现的原创源代码受当前 [PolyForm Noncommercial](../LICENSE) 许可约束；此前 MIT 版本保留各自既有权利。截图来自实际应用和专门准备的虚构账本，不代表真实个人财务数据；截图中出现的 Apple 系统符号、字体及其他第三方内容仍受各自权利限制。银行图片由用户自行添加，用户应具有相应使用权。

后续新增素材应同时记录来源、适用许可或授权证明；不能仅凭可下载或可访问就标注为“无版权”或“开源”。

## GitHub mark

The GitHub mark is provided by [Primer Octicons](https://github.com/primer/octicons) under the MIT license. Copyright (c) 2026 GitHub Inc. The full license accompanies the app. The mark identifies GitHub links and does not imply endorsement.
