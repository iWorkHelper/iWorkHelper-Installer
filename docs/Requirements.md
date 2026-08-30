# 需求与验收矩阵

正式入口是单一 EXE。首屏选择简体中文（默认）或 English；后续使用线性向导，并在配置页集中选择 Scope、Excel/Outlook Feature、路径及查看环境检测。Scope、路径、MSI 注册范围必须一致，提权由 per-machine 或目标目录实际写权限决定。

## 支持范围

- Windows 10 1809+ / Windows 11 x64 客户端。
- Microsoft Office 2016+ x64，当前仅检测 Office 16.0 的 64 位注册表视图。
- .NET Framework 4.8+，`Release >= 528040`。
- Microsoft Visual Studio 2010 Tools for Office Runtime v4R。
- 统一 EXE 为正式入口；MSI 是 Bundle 内部主包，不作为用户发布入口。
- Excel 与 Outlook 是一个 MSI 中两个相互独立、可修改的 Feature。
- 安装范围为当前用户或所有用户；当前用户使用 LocalAppData + HKCU，所有用户使用 Program Files x64 + HKLM。
- UI 文化为 `zh-CN` 与 `en-US`。

## 验收状态

| 项目 | 状态 | 证据/备注 |
|---|---|---|
| 精确 Payload 收集 | 已构建验证 | 4 个 Excel 文件、17 个 Outlook 文件 |
| Excel / Outlook 独立 Feature | 已数据库验证 | 两个顶级 Feature，组件集合无交叉 |
| 双作用域目录与 HKMU 注册 | 已数据库/Bundle 验证 | MSI 与 Bundle 均为 `perUserOrMachine` |
| Windows / Office / .NET / VSTO 检测 | 已数据库/Bundle 验证 | 含 Click-to-Run x64 和 VSTO 32 位视图兼容 |
| en-US / zh-CN localization | 已数据库验证 | 中文 MST 已成功应用并验证 ProductLanguage/Feature 标题 |
| MSI ICE | 已通过 | WiX 7 `wix msi validate` 无错误 |
| 安装 / Modify / Repair / Remove / Upgrade | 未验证 | 当前非管理员会话中 Windows Installer 客户端超时，未产生事务或日志 |
| Excel only / Outlook only / Both | 未验证 | 未成功启动真实 MSI 事务 |
| 中文 / 英文交互界面 | 未验证 | 数据库资源已验证，尚未人工操作 UI |
| per-user / per-machine 真实安装 | 未验证 | per-user 启动被环境阻塞；per-machine 需要管理员会话 |
