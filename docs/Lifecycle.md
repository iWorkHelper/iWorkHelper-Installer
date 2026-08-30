# Installer 生命周期、ARP 与安装位置

## 唯一 ARP 入口

Windows“已安装的应用”只显示 Burn Bundle。内部 MSI 保持完整 Windows Installer registration，但通过 Bundle `MsiPackage Visible="no"` 和 MSI `ARPSYSTEMCOMPONENT=1` 隐藏，不能删除 MSI registration。Excel 与 Outlook 只是同一 MSI 的独立 Feature，不创建 ARP 项。

旧版本出现两个同名条目的直接原因是 `MsiPackage Visible="yes"`：一个条目属于 Bundle，另一个属于 MSI。识别时必须核对 `WindowsInstaller`、`BundleUpgradeCode`、UninstallString 和注册根，不能只看 DisplayName。

## 启动 Action

BA 在 Detect 完成后读取 Burn `WixBundleCommandLineAction`（规划后另记录 `WixBundleAction`）并记录 requested action：

- 首次普通启动：Install；
- 已安装后普通启动：配置页用于 Modify；
- ARP `/uninstall`：语言确认和 Detect 后直接进入卸载确认，不再进入首次安装配置；
- `/repair`：直接进入修复确认；
- Upgrade：由 Burn related-bundle planning 和 MSI MajorUpgrade处理。

Burn 在 Upgrade 中会以隐藏 UI 启动旧 related bundle 的 `/uninstall`。BA 必须遵守 `WixBundleUILevel`：非完整 UI 时不显示语言/配置窗口，Detect 后直接执行命令 Action 并在 ApplyComplete 后退出，否则升级会被旧版本的首次安装界面阻塞。

Modify 时仅设置 `PlanMsiFeature` 不足以让已安装包执行；BA 同时在 `PlanPackageBegin` 把主 MSI 请求为 `ForcePresent`，否则 Burn 会规划 `execute=None`，UI 看似成功但 Feature 文件不会变化。Outlook edition 切换由同一次事务把旧版 Feature 设为 Absent、新版设为 Local，避免两个注册组件或 Payload 同时残留。

最终 Plan 日志同时记录 requested/planned action、requested/planned scope、elevation 和路径。

## 安装路径链路

路径链路固定为：BA 输入框 → persisted Burn `InstallFolder` → Bundle `MsiProperty INSTALLFOLDER=[InstallFolder]` → MSI public property `INSTALLFOLDER` → `ExcelFolder`/`OutlookLocalFolder`/`OutlookLocalOnlineFolder` → Component/File。

`INSTALLFOLDER` 位于 `ProgramFiles64Folder` 下，以符合 Windows Installer 5.0 dual-purpose authoring；Burn 传入绝对自定义路径时会覆盖默认目录解析。MSI 在 CostFinalize 后设置 `ARPINSTALLLOCATION=[INSTALLFOLDER]`，verbose log记录最终目录。

Bundle 持久化 `InstallFolder` 和 `InstallPerMachine`。维护时优先使用 `WixBundleDetectedScope` 和已持久化路径，不重新计算 LocalAppData/Program Files 默认值。MajorUpgrade 的新 Bundle Id 不继承旧 Bundle persisted variables，因此 BA 还通过固定 MSI UpgradeCode 枚举已安装产品并读取 MSI `InstallLocation` 作为升级路径回退。只有首次安装且用户尚未编辑路径时，切换 Scope 才同步切换默认目录。

Outlook 版本同样不能在维护或升级时回落到 UI 默认值。当前 ProductCode 的维护使用 Burn 检测到的 `OutlookFeature` / `OutlookLocalOnlineFeature` 状态；MajorUpgrade 时 Burn 只报告新 ProductCode 的 Feature 为 Absent，因此 BA 通过固定 MSI UpgradeCode 枚举 related product，并调用 `MsiQueryFeatureState` 读取旧 `ExcelFeature`、`OutlookFeature` 和 `OutlookLocalOnlineFeature`。HKMU `Software\iWorkHelper\Installer\OutlookEdition` 记录 `Local` 或 `LocalOnline` 作为诊断与恢复信息。旧安装器只有 `OutlookFeature`，因此升级时明确映射为 Local。

## 开发测试清理

`scripts/Clear-DevelopmentInstall.ps1` 默认只列出精确匹配 Bundle UpgradeCode 和 MSI UpgradeCode 的注册。人工确认后使用 `-Execute` 调用各自已注册的卸载命令。只有显式提供 `-InstallFolder`、目录末级名为 `iWorkHelper` 且 Office Add-in Manifest 指向该目录时，脚本才允许清理孤立文件夹；不得用宽泛注册表或目录删除替代。
