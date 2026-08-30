# 需求与验收矩阵

正式入口是单一 EXE。首屏选择简体中文（默认）或 English；后续使用线性向导，并在配置页集中选择 Scope、Excel/Outlook Feature、路径及查看环境检测。Scope、路径、MSI 注册范围必须一致，提权由 per-machine 或目标目录实际写权限决定。

## 支持范围

- Windows 10 1809+ / Windows 11 x64 客户端。
- Microsoft Office 2016+ x64，当前仅检测 Office 16.0 的 64 位注册表视图。
- .NET Framework 4.8+，`Release >= 528040`。
- Microsoft Visual Studio 2010 Tools for Office Runtime v4R。
- 统一 EXE 为正式入口；MSI 是 Bundle 内部主包，不作为用户发布入口。
- Excel 与 Outlook 是一个 MSI 中相互独立、可修改的 Feature。Outlook 有互斥的本地版与本地+网络版：未选择 Outlook 时两者均不安装；选择 Outlook 时只允许安装其中一个。首次安装默认勾选 Excel、Outlook 和“本地 + 网络版”；维护与升级保留已安装的实际 edition。
- 安装范围为当前用户或所有用户；当前用户使用 LocalAppData + HKCU，所有用户使用 Program Files x64 + HKLM。
- UI 文化为 `zh-CN` 与 `en-US`。

## 验收状态

| 项目 | 状态 | 证据/备注 |
|---|---|---|
| 精确 Payload 收集 | 已构建验证 | 4 个 Excel 文件、17 个 Outlook Local 文件、17 个 Outlook LocalOnline 文件，三个目录独立且两个 Outlook 主程序集哈希不同 |
| Excel / Outlook 独立 Feature | 已数据库/真实验证 | `ExcelFeature`、`OutlookFeature`（Local）和 `OutlookLocalOnlineFeature`；Outlook 两版互斥且不与 Excel 共享组件 |
| 双作用域目录与 HKMU 注册 | 已数据库/Bundle 验证 | MSI 与 Bundle 均为 `perUserOrMachine` |
| Windows / Office / .NET / VSTO 检测 | 已数据库/Bundle 验证 | 含 Click-to-Run x64 和 VSTO 32 位视图兼容 |
| en-US / zh-CN localization | 已数据库验证 | 中文 MST 已成功应用并验证 ProductLanguage/Feature 标题 |
| MSI ICE | 已通过 | WiX 7 `wix msi validate` 无错误 |
| 安装 / Modify / Repair / Remove / Upgrade | 已部分真实验证 | 1.0.8 per-user edition Modify/Repair/Remove 通过；1.0.6/1.0.7 → 1.0.8 的 Local 与 LocalOnline Upgrade 均通过 |
| Excel / Outlook edition 组合 | 已真实验证 | Excel only、Outlook Local only、Outlook LocalOnline only、Excel + Local、Excel + LocalOnline 均核对文件/注册/Feature 状态 |
| 中文 / 英文交互界面 | 已 UI 自动化验证 | 中文默认；中英文均显示 Outlook edition 控件，默认 Local，取消 Outlook 后控件禁用且选择保留 |
| per-user / per-machine 真实安装 | 已部分真实验证 | per-user 1.0.8 edition 生命周期通过；per-machine scope/UAC 已在 1.0.4 验证，本次 edition 矩阵未在管理员上下文重跑 |
