# Installer UI、Scope 与提权

最终 EXE 使用 WiX 7 out-of-process 自定义 WPF Bootstrapper Application，不使用 WixStdBA。流程固定为：语言选择 → 安装配置 → 确认 → 进度 → 完成。首屏默认简体中文，可切换 English；后续页面、错误和维护操作使用所选语言。

配置页集中显示安装范围、Excel/Outlook 选择、安装路径和 Windows/.NET/Office/VSTO 检测结果。首次安装默认勾选 Excel、Outlook 和互斥选项中的“本地 + 网络版”（English: `Local + Online`）；“本地版 / 本地 + 网络版”只在勾选 Outlook 后启用。取消 Outlook 会禁用两个单选项但保留其 UI 状态，Plan 时两个 Outlook Feature 都设为 Absent。维护模式在同页提供 Modify、Repair、Remove，不打开 MSI 内部 FeatureTree UI。

BA 使用 `Plan(action, BundleScope.PerUser/PerMachine)` 决定 configurable-scope MSI 的真实作用域。per-user 默认目录为 `LocalAppData/Programs/iWorkHelper`，per-machine 默认目录为 `Program Files x64/iWorkHelper`。切换 Scope 会切换默认路径；用户可继续选择任意绝对路径。

BA 在开始安装前对目标目录或最近存在的父目录执行可删除的写入探测。per-machine 始终提权；per-user 仅在当前令牌不可写时调用 Burn `Elevate`。用户拒绝 UAC 时返回配置页，保留 Scope、Feature 和路径，不静默改目录。

`InstallFolder`、语言、Feature 选择和 `OutlookEdition` 是 Bundle persisted variables；MSI 接收 `[InstallFolder]` 与 `[OutlookEdition]`，Feature 状态通过 `PlanMsiFeature` 设置。`InstallOutlook=0` 的优先级高于保留的 edition 值。MSI 默认路径动作仅在没有传入 `INSTALLFOLDER` 时运行，避免维护或升级路径漂移。

中文 MST 是 Bundle 内嵌 Payload，由 `SelectedLanguage` 条件传给 MSI。正式安装只需 EXE；MSI/MST 仅用于开发诊断。

BA 目标为 .NET Framework 4.6.2，使其能在受支持的 Windows 10 1809 基线上先显示语言页和缺失提示。插件和 MSI 的最低运行要求仍是 4.8。

Windows x64、.NET 4.8、Office x64 或 VSTO Runtime 缺失均属于阻止条件。.NET 与 VSTO 缺失提示只打开对应 Microsoft 官方页面，不下载或启动 Runtime 安装包，避免为普通 per-user 安装引入系统级 prerequisite 提权。

BA 日志记录用户选择、目录写入探测、是否请求 elevation、`WixBundlePlannedScope` 和 `WixBundleElevated`。MSI verbose log用于核对 `ALLUSERS`、`MSIINSTALLPERUSER`、最终 `INSTALLFOLDER` 以及是否出现 `MsiRunningElevated`。Scope 始终来自 Burn `Plan(action, BundleScope)`，不得由路径推断。
