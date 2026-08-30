# 安装器架构

## 技术选择

目标版本为 WiX Toolset 7.0.0。Bundle 使用 out-of-process 自定义 WPF BA，以支持首屏语言、线性配置、Feature、动态目录和按需提权；WixStdBA 与 MSI FeatureTree 不参与正式用户界面。BA 通过 `Plan(action, scope)` 为同一个双作用域 MSI 规划 per-user 或 per-machine 安装。`WixStdBAScope` 是 WixStdBA 的专用约定，不应在自定义 BA 中重新声明；本项目用 persisted `InstallScope` 保存等价 UI/诊断值，真正控制 Burn scope 的是 `Plan` 的 `BundleScope` 参数。

两个 `.wixproj` 均使用 `Project Sdk="WixToolset.Sdk/7.0.0"`，WiX 源文件使用 `http://wixtoolset.org/schemas/v4/wxs` schema，BA API 与 WiX extensions 均以 7.0.0 NuGet `PackageReference` 声明。因此技术栈是现代 WiX 7 SDK-style，而不是 WiX v3 legacy。命令行项目系统由 WiX SDK/NuGet 提供；Visual Studio 内的 `.wixproj` 加载、模板和属性页由 HeatWave for Visual Studio 提供。

MSI 先分别构建 en-US 与 zh-CN，再以英文 MSI 为基准生成 language MST。Bundle 内含一个主 MSI 和中文 MST；选择简体中文时按 `SelectedLanguage` 传入 transform。这样不同语言仍维护同一个 MSI 产品身份和升级链。

WiX 7 二进制发行版附带 OSMF EULA/维护费要求。项目所有者确认合规前不得还原或使用这些包；参见 `KnownIssues.md`。

## 生命周期分工

- Burn EXE：检测 Windows/.NET/Office/VSTO Runtime、阻止缺少 Runtime 的安装、选择安装范围、按需提权、缓存、重启协调、主 MSI 生命周期。
- MSI：安装插件文件、Excel/Outlook Feature、VSTO 注册、Modify/Repair/Remove 和 MajorUpgrade。
- Bundle Chain 只包含主 MSI，不包含会迫使普通 per-user 安装提权的 Runtime 包。.NET 4.8 或 VSTO Runtime 缺少时，BA 显示对应 Microsoft 官方页面并阻止当前安装；用户安装 Runtime 后重新运行安装器。
- MSI 不链接 WixUI/FeatureTree；所有交互和 Feature 规划均由 BA 完成，避免引入不使用的 MSI 内部 UI 和维护入口。
- Bundle 是唯一可见的 ARP 产品；内部 MSI 设置 `Visible="no"`/`ARPSYSTEMCOMPONENT=1`，保留注册供 Burn、Repair、MajorUpgrade 和 Uninstall 使用。

## 双作用域 MSI

MSI `Scope="perUserOrMachine"` 默认当前用户，对应创作值 `ALLUSERS=2`、`MSIINSTALLPERUSER=1`，并使用 Windows Installer 5.0 schema。`INSTALLFOLDER` 位于可按上下文重定向的 `ProgramFiles64Folder` 目录树下；在 per-user 上下文中 Windows Installer 将该已知目录映射到当前用户的 Programs 目录。`MSIDEPLOYMENTCOMPLIANT=1` 明确声明包遵循 UAC 创作规则。

Summary Information Word Count 保留压缩源 bit 1，并设置 no-elevation bit 3，最终值为 `10`。没有 bit 3 时，Windows Installer 会在 per-user MSI 初始化阶段自行请求 UAC，甚至早于 MSI verbose 日志建立。per-machine 分支由 BA 在 Burn Plan 后显式请求 elevation；提升成功后才执行同一个双作用域 MSI。

`INSTALLFOLDER` 默认是 `[LocalAppDataFolder]Programs\iWorkHelper`；当规划为 per-machine 时切换到 `[ProgramFiles64Folder]iWorkHelper`。注册根使用 `HKMU`，由 Windows Installer 随范围写入 HKCU 或 HKLM。per-user 执行时 Windows Installer 会把创作时的 `ALLUSERS=2`/`MSIINSTALLPERUSER=1` 归一化为 per-user 上下文；per-machine 则使用 `ALLUSERS=1`。

自定义路径由 BA persisted `InstallFolder` 通过 Bundle `MsiProperty` 映射到 MSI public `INSTALLFOLDER`。Excel/Outlook 的全部文件组件分别挂在其子目录；MSI 设置 `ARPINSTALLLOCATION`，维护和升级优先复用 Burn persisted path，不从路径反推 Scope。

Bundle 日志记录 UI scope、WixStdBA 等价 scope、Authored/Detected/Planned Scope、elevation、每个 package 的 plan/cache/execute 边界。MSI verbose log 通过 `IWORKHELPER_*` 诊断属性记录 Burn scope，并在 CostFinalize 后生成 `IWORKHELPER_INSTALLCONTEXT`，明确写出最终 `ALLUSERS`、`MSIINSTALLPERUSER` 和 `INSTALLFOLDER`。development MSI 设置 `MsiLogging=voicewarmupx!`，确保 client-side per-user 首次安装也生成独立 verbose log。这些属性和日志设置只用于诊断，不参与 Scope 决策。

所有文件组件与注册组件都显式为 64 位。当前不写 WOW6432Node，因为产品明确不支持 32 位 Office。

## Feature 隔离

- `ExcelFeature` 只引用 Excel Payload 和 Excel 注册组件。
- `OutlookFeature` 只引用 Outlook Payload 和 Outlook 注册组件。
- 两者没有父子关系、共享注册组件或互相引用，因此 Modify/Repair/Remove 的 Feature 状态可独立处理。

## 检测

Bundle 使用 64 位注册表视图：

- Windows：`InstallationType=Client` 且 `CurrentBuildNumber >= 17763`，并检查原生机器为 AMD64。
- .NET：`NDP\v4\Full\Release >= 528040`；DWORD 在 MSI 条件中使用 `#528040`，Burn 直接比较注册表搜索结果（WiX 7 不接受旧式 `numeric Variable` 前缀）。
- VSTO：同时搜索 64 位与 32 位注册表视图中的 `SOFTWARE\Microsoft\VSTO Runtime Setup\v4R\Version`，兼容 Runtime 实际写入 WOW6432Node 的机器。
- Office x64：传统安装检测 64 位视图的 `Office\16.0\Common\InstallRoot\Path`；Microsoft 365/Click-to-Run 另检测 `Office\ClickToRun\Configuration\Platform=x64`。

MSI 重复 .NET/VSTO/Office/Windows 检查，避免用户绕过 EXE 直接启动 MSI。
