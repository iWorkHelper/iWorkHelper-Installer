# 测试与验证

## 自动验证

```powershell
.\tests\Test-InstallerSources.ps1
```

当前机器无发布证书时，VSTO Release Build 会按预期失败；可用 `build.ps1 -SkipAddinBuild -SkipInstallerBuild` 对已有、已签名 Release 输出执行 Payload 收集与安装器静态检查。

当前 development build 的自动验证结果：

- 2026-08-30 已验证 `dotnet restore iWorkHelper-Installer.slnx`、BA Release、MSI Release、Bundle Release 与 `Release|x64` Solution Rebuild；均为 0 警告、0 错误。Solution Rebuild 确认三个项目均实际参与生成，而非仅加载 `.slnx` 或只构建 BA。
- 当前 VS 2022 17.14 实例已安装 `.NET 桌面开发`、`Office/SharePoint 开发` 和 .NET Framework 4.8 targeting pack/SDK，但未发现 HeatWave/WiX VSIX；因此源码/CLI 构建已通过，IDE 加载仍须人工安装 HeatWave 后验证。
- 两个 VSTO Release Build 均为 0 警告、0 错误，deployment/application manifests 使用本机开发自签名证书。
- MSI 和 Bundle 均为 0 警告、0 错误构建。
- MSI ICE 验证通过。
- 数据库验证确认两个顶级 Feature 无共享组件、`ALLUSERS=2`/`MSIINSTALLPERUSER=1` 双作用域、`MSIDEPLOYMENTCOMPLIANT=1`、Windows Installer 5.0、可重定向的 `ProgramFiles64Folder`、Summary Word Count=`10`（压缩源 + per-user 不提权）、HKMU 注册、LaunchCondition 和中文 MST。
- Bundle 解包验证确认 scope 为 `perUserOrMachine`、Chain 只有主 MSI且没有任何 Runtime/ExePackage、中文 transform 条件正确。
- Bundle 解包验证确认自定义 BA 及依赖、持久化 UI 变量、`INSTALLFOLDER` 传递和中文 MST 全部内嵌。
- 开发自动化可用 Burn `Variable=Value` 语法覆盖 scope、路径、语言和 Feature；变量同时保持 persisted，正式 UI 与无人值守测试走同一条 Plan/MsiProperty 链路。
- Bundle/MSI 验证确认内部 MSI 为隐藏系统组件、Bundle 为唯一 ARP 入口，并检查 persisted Scope/path 变量。
- Bundle 版本、Chain MSI 版本和确定性 ProductCode 必须与构建参数一致；Bundle 构建禁止用默认属性重新构建已经生成的 MSI。
- MSI 数据库资源审计确认 Registry 表只使用 HKMU、无 Service/ODBC machine-only 表、无 deferred/elevated custom action；现有 CustomAction 均为 immediate type-51 属性赋值。
- Windows UI Automation 已真实验证：首屏为语言选择、简体中文默认选中；切换 English 后配置页及 Scope/Feature 文案为英文；切换 All users 后默认路径变为 Program Files。
- 实际启动最终 EXE 并停留在检测/UI 阶段：.NET Release、Windows x64/Build、Office x64、VSTO Runtime 条件均求值为 true，Burn `Detect complete` 返回成功；未执行 Apply，不计为安装通过。
- 已针对 WiX 7 运行时条件语法加入回归检查，Bundle 条件中禁止旧式 `numeric Variable` 前缀。

1.0.3 的最终 MSI 没有设置 Summary Word Count bit 3。真实用户操作中 Burn 虽已正确规划 PerUser，Windows Installer 仍在 MSI 初始化前自行发起 UAC；拒绝后返回 `0x80070642`，且来不及创建 package verbose log。1.0.4 将 Word Count 从 `2` 修正为 `10` 并加入数据库断言。语言 MST 改写 ProductCode 的旧问题也已固定并有回归检查。

最终创作版本已通过构建、ICE/数据库和 Bundle 解包验证。早期测试曾因错误 MSI 上下文和残留注册无法确认零 UAC；后续清理并修复 ProductCode、Scope 和路径链路后，已取得 per-user 默认/自定义目录 `WixBundleElevated=0` 且 Apply 成功的有效日志。

### 1.0.4 Scope/UAC 根因与真实验证

修复前日志 `.local/logs/uac-1.0.4/before-fix-burn.log` 显示：UI scope/等价值为 PerUser、`WixBundlePlannedScope=2`、`WixBundleElevated=0`、Chain 只有 scope=PerUser 的 `iWorkHelperMsi`；Apply 调用 MSI 后立即收到 1602。日志没有 `i010`，专属 MSI 日志也未建立。数据库检查同时确认该 MSI Word Count=`2`，因此首次提权点是 Windows Installer 初始化，不是 Bundle Plan/Apply、prerequisite 或 BA `engine.Elevate`。

1.0.4 最终 EXE 在中等完整性、非管理员令牌下完成真实 per-user 默认安装和 Remove：

- 安装与 Remove 均返回 0，全程没有 `i010`/elevated engine；`WixBundlePlannedScope=2`、`WixBundleElevated=0`。
- MSI 命令行含 `MSIINSTALLPERUSER=1`；Windows Installer 把 `ALLUSERS=2` 归一化为空，并记录 `Package is marked as LUA installation capable with no elevation required`。
- 最终 `IWORKHELPER_INSTALLCONTEXT` 为 PerUser，文件进入 LocalAppData，Excel/Outlook Add-in 注册进入 HKCU，HKLM 无对应项。
- Remove 后安装目录、Add-in 注册以及 Bundle/隐藏 MSI registration 均清除。

同一最终 EXE 还完成真实 per-machine 默认安装和 Remove：

- `WixBundlePlannedScope=1` 后出现 `i010: Launching elevated engine process`；用户批准 UAC 后记录 `i011`，`WixBundleElevated=1`。
- MSI 接收空的 `MSIINSTALLPERUSER`，文件进入 Program Files x64，Excel/Outlook 注册进入 HKLM；安装和 Remove 均返回 0。
- Remove 后 Program Files 目录、HKLM Add-in 注册以及 Bundle/隐藏 MSI registration 均清除。

最终脱敏日志位于 `.local/logs/uac-1.0.4/`：`final-per-user-install*.log`、`final-per-user-remove*.log`、`per-machine-uac-final*.log` 和 `per-machine-remove*.log`。`.local` 已被 `.gitignore` 排除。

### 历史 1.0.3 诊断

1.0.2 的有效 per-user 日志显示：EXE 以普通进程启动，UI 请求 `PerUser`，Plan begin 为 `PerUser`，`WixBundlePlannedScope=2`，`WixBundleElevated=0`，Chain 只执行 `iWorkHelperMsi`；MSI 命令行含 `MSIINSTALLPERUSER=1`，MSI 记录包为 LUA capable/no elevation required。因此这些日志中没有 UAC：既没有 BA 调用 `Elevate`，也没有 Burn elevated companion process 或 machine prerequisite。用户看到 UAC 时必须先核对实际运行版本和对应日志，不能用安装目录推断上下文。

1.0.3 使用 BA scope 日志和 Burn 原生 Plan/Apply/package/elevation 日志。per-user 可写目录必须同时满足：UI/诊断 scope 为 PerUser、planned scope 2、elevated 0、package scope PerUser、MSI context PerUser；per-machine 的 planned scope 应为 1，并允许 Burn 创建 elevated companion process。

1.0.3 在中等完整性令牌下完成以下真实验证，均未出现 UAC，且 Apply 返回 0：

- per-user 默认 LocalAppData；文件位于默认目录，HKCU Excel/Outlook 注册正确。
- per-user 可写自定义目录；UI 实际编辑路径后安装，文件与 HKCU Manifest 均使用最终目录，HKLM 无对应 Add-in 注册。
- per-user Modify、Repair、Remove；三者 planned scope 均为 2、`WixBundleElevated=0`，维护期间保持自定义路径，Remove 后文件与 HKCU 注册清除。

首次 MSI 入口属性为 Property 表 `ALLUSERS=2`、命令行 `MSIINSTALLPERUSER=1`；Windows Installer 选择 per-user context 后把 `ALLUSERS` 归一化为空。MSI 服务器日志中的 `MsiRunningElevated=1` 表示 Windows Installer 服务端执行状态，不等同于出现 UAC；本次交互安装全程没有 UAC，Burn 也始终为 `WixBundleElevated=0`。

已脱敏的历史验证日志位于 `.local/logs/uac-1.0.3/`：default/custom Bundle 与 MSI verbose log，以及 Modify/Repair/Remove Bundle log。原始临时日志不进入源码或发布产物。

1.0.1/1.0.2 生命周期修复后的实际结果：

- per-user 默认 LocalAppData：Excel/Outlook 文件实际存在于默认目录，Apply 返回 0，无 Bundle elevation。
- per-user 自定义 LocalAppData：全部 Excel/Outlook Payload 和 HKCU Manifest 均指向所选目录；Bundle 日志中的 Burn variable、MSI property 和规划路径一致。
- ARP：注册层面同时存在可见 Bundle 和 `SystemComponent=1` 的隐藏 MSI；Windows 应用列表只应显示 Bundle。Excel/Outlook 没有独立产品注册。
- 从 Bundle 实际 `UninstallString /uninstall` 启动后，语言确认后直接进入卸载确认；日志 requested/planned action 均为 Uninstall。Apply 返回 0，Bundle、MSI、文件和测试 Add-in 注册清除。
- Modify 首次实测发现仅设置 Feature plan 会得到 package `execute=None`；已增加 `RequestState.ForcePresent`。修复后尚未在清理完旧 dependency provider 的干净事务中复测。
- Upgrade 实测发现旧 related bundle BA 不遵守隐藏 UI并阻塞父升级；已增加 `WixBundleUILevel` headless lifecycle。当前机器存在多轮中断测试留下的 Burn dependency provider，最终升级复测保留为未验证。

检查双 Feature、双作用域、检测属性、HKMU、`vstolocal`、LoadBehavior、危险的宽泛 Payload 复制、凭据样式及用户绝对路径。构建后还应运行 WiX 验证/ICE，并把无抑制的警告作为失败处理。

## 真实安装矩阵

在干净的 Windows 10/11 x64 虚拟机中，分别以标准用户和管理员测试。每个动作保存 Bundle 与 MSI verbose log，并检查文件、注册表、Apps & Features 和 Office COM Add-ins：

安装前先运行 `scripts/Clear-DevelopmentInstall.ps1` dry-run，核对精确 Bundle/MSI 标识；仅在开发测试环境确认后使用 `-Execute`。安装后记录 Bundle 与隐藏 MSI 的 DisplayName、版本、卸载命令、Id 和 Scope，确认 ARP 只显示 Bundle。

1. Excel only、Outlook only、Excel + Outlook。
2. per-user：文件在 LocalAppData，注册在 HKCU，不影响另一用户。
3. per-machine：触发提权，文件在 Program Files x64，注册在 HKLM，多用户可见。
4. Modify：逐一添加/移除 Feature，确认另一 Feature 文件与注册不变。
5. Repair：删除一个受控文件后修复，确认恢复且 Feature 状态不变。
6. Remove：文件、注册与 ARP 项清理；外部 .NET/VSTO Runtime 保留。
7. Upgrade：先装旧版本及三种 Feature 组合，再装新版本，确认没有并存产品、Feature 状态符合预期、用户配置保留。
8. 在 zh-CN 与 en-US 系统/命令行语言下检查 Bundle 和 MSI UI。
9. 缺少 .NET 或 VSTO Runtime 时必须阻止安装、显示中英文说明和对应 Microsoft 官方页面入口，不得自动下载、安装或因此触发 UAC。
10. 分别在 Windows x86/ARM64、Office x86、无 Office、Office 版本不支持的机器验证阻止消息。

动态提权必须在隔离 VM 中验证：per-user 默认目录无 UAC；per-machine 有 UAC；per-user 指向受保护目录时有 UAC；可写自定义目录无 UAC；拒绝 UAC 后回到配置页且路径不变。静态调用检查或目录写入探测不能替代真实 UAC 测试。

Excel 和 Outlook 必须完全退出后执行安装维护。Outlook 还要检查 Resiliency/禁用项是否影响加载，不能把 Office 自行禁用误判成注册失败。
