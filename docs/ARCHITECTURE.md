# 源码结构

FinTrack 使用 SwiftUI、SwiftData、AppKit 和 Apple 系统 SDK。macOS 目标为 `FinTrack`，工程配置在 `Project/project.yml`。

```text
Sources/
  App/          应用入口、窗口与生命周期
  Core/         记账规则、汇率、持久化、偏好和系统服务
  Features/     按功能组织的页面、状态与服务
  Components/   复用控件、设计基础和图片处理
  Shared/       共享数据模型及通用计算规则
Resources/      应用图标、本地化和货币旗帜资源
Project/        XcodeGen 构建定义
scripts/        公开构建与网站校验工具
docs/           构建、安装和数据说明
website/        产品官网的静态源码
.github/        构建及 GitHub Pages 工作流
```

`Features/` 包含概览、账目、存款、贷款、周期记账、统计、设置、汇率、菜单栏、快速记账与数据管理。`Shared/` 保留单一的共享模型与业务规则，避免维护重复实现。

八个 SwiftData 模型为 Account、Transaction、Category、Goal、FinancialProfile、RecurringTransaction、DepositRecord 和 LoanRule。持久化路径及用户数据管理见[数据与隐私](PRIVACY.md)。

构建时直接引用 `Sources/` 与 `Resources/`，由 XcodeGen 递归生成引用；新增文件通常不需要维护手写的文件列表。修改资源时应同步核对资源加载方式及授权依据。
