# 已知限制与踩坑

- 自定义 BA 目标为 .NET Framework 4.6.2，以便 .NET 4.8 缺失时仍能显示语言页和 Microsoft 官方下载入口；尚未在实际移除 4.8 的 Windows 10 1809 VM 上验证阻止流程。

## 当前阻塞项

1. 当前使用开发用途自签名 VSTO manifest 证书。受控测试机必须预先信任该证书；正式发布必须替换为受信任的 VSTO 发布证书。
2. MSI 与 Bundle 开发构建暂不做 Authenticode 签名，Windows 会显示未知发布者警告。
3. VSTO Runtime 不自动下载或安装。缺少时安装器只指向 Microsoft 官方下载页并阻止继续。

## 尚未验证

- 最终 Bundle 的全套范围、Feature 和自定义目录交互矩阵。
- 全部真实安装生命周期、Office 加载、重启恢复和升级状态迁移。
- 中文/英文交互界面的人工视觉检查。
- per-user 受保护自定义路径、拒绝 UAC、Upgrade 和 Office 实际加载仍需在隔离 VM/受控机器验证。1.0.4 的 per-user 默认路径安装/Remove 已真实验证为 planned scope 2 且全程无 UAC；per-machine 默认路径安装/Remove 已真实验证为 planned scope 1 且按预期请求 UAC。
- 1.0.3 已真实通过 per-user 可写自定义路径、Modify 和 Repair；这些场景尚未用 1.0.4 重新回归。related-bundle headless Upgrade 修复已构建和静态验证，但尚未完成干净的最终升级实测。
- Office Click-to-Run/Microsoft 365 已覆盖常见的 `Platform=x64` 注册布局，但仍需在更多 Office 更新通道和永久版上做真实安装验证。

## 踩坑结论

- Visual Studio 报项目类型 GUID `930c7802-8a8c-48f9-8165-68863bccd9dd` “找不到此项目类型所基于的应用程序”时，应安装/启用 HeatWave for Visual Studio。WiX 7 SDK NuGet 包能让 `dotnet build` 成功，但不会向 Visual Studio 注册 `.wixproj` 项目系统；不得通过改扩展名、改为 C# Project Type GUID 或从 Solution 删除项目规避。
- `.slnx` 必须显式把 WiX 项目纳入 `Release|x64` Build，并把解决方案平台映射到项目 `x64`；否则 Solution Build 可能只构建 BA，或把 MSI 当作 AnyCPU/32 位包并触发 ICE80。
- Fragment 中的搜索通过 `RegistrySearchRef` 显式引用，避免链接器裁剪。
- .NET Release 是 DWORD；MSI 比较必须使用 `#528040`，Burn 直接比较注册表搜索结果。
- WiX 7 Burn 不接受条件中的旧式 `numeric Variable` 前缀，且 util `RegistrySearch` 不支持 `VariableType` 属性。条件应直接写 `NetFrameworkRelease >= 528040` 或 `WindowsCurrentBuild >= 17763`；Bundle 验证会拒绝任何残留的旧式前缀。
- WiX 7 Burn 条件中的字符串字面量必须使用双引号；在 XML 属性中写作 `&quot;Client&quot;`、`&quot;x64&quot;`，单引号会导致运行时条件解析失败。
- HKMU 组件不能混入固定 HKCU/HKLM key path，否则双作用域会失真。
- 2026-08-30 真实日志根因：用户选择 PerUser 后 Burn 的 `WixBundlePlannedScope=2`、`WixBundleElevated=0` 均正确，但内部 MSI 的 Summary Word Count 为 `2`（压缩源、未设置 bit 3），Windows Installer 因而把包标记为“可能需要提升”；UAC 首次发生在 `iWorkHelperMsi` 初始化、MSI 事务和专属 verbose 日志建立之前。用户拒绝后 Burn 收到 `0x80070642`，且没有 `i010`/elevated-engine 记录。修复是保留压缩位并设置 bit 3，使 Word Count 为 `10`；per-machine 仍由 BA 在 `Plan` 后显式调用 Burn elevation，再执行同一 MSI。
- Windows Installer 选定 per-user context 后会把创作值 `ALLUSERS=2` 归一化为空；日志后段单独出现 `MSIINSTALLPERUSER property is not valid for UAC compliant package` 不能作为 machine context 的证据，必须结合命令行初始值、ALLUSERS 转换、实际注册根和文件目录判断。
- Burn configurable scope 与安装路径是独立概念。日志必须同时核对 `WixBundlePlannedScope=2`、`WixBundleElevated=0` 和 MSI 实际上下文；不能因为目录在 LocalAppData 就推断为 per-user。
- 自定义 BA 不依赖 WixStdBA 控件来规划 scope：不得自行声明保留名称 `WixStdBAScope`，否则 Burn 会在日志初始化前返回 `0x80070057`。项目用 `InstallScope` 保存 UI/诊断等价值；真正的 configurable-scope 决策是 `Plan(action, BundleScope.PerUser/PerMachine)`。不得只改目录或 `InstallPerMachine` 而仍用默认 Plan scope。
- Bundle 构建的 ProjectReference 曾可能用默认属性或增量缓存复用旧 MSI，使 EXE 文件名/Bundle 版本与 Chain MSI 版本、ProductCode 不一致。统一构建入口现在对 MSI/Bundle 强制 Rebuild，先生成确定性 MSI，再以 `BuildProjectReferences=false` 绑定 Bundle，并在解包测试中核对三个身份；旧构建不得用于 Scope/UAC 结论。
- `engine.Elevate` 只允许在 per-machine 或写入探测确认目录不可写时调用。开发日志通过 `elevationRequested`、Burn 原生 Apply/elevation 记录和 `WixBundleElevated` 区分“BA 决定请求 UAC”和实际提升；缺少 .NET/VSTO Runtime 只阻止安装并打开 Microsoft 页面，Chain 不包含 Runtime package。
- 分别构建本地化 MSI 时不能让 WiX 为每种语言自动生成不同 ProductCode。否则 MST 会改写 ProductCode，Burn 仍按基础 MSI 身份检测，维护模式会误判产品 Absent。统一构建入口按版本生成一个 ProductCode并传给所有语言，数据库测试在应用 MST 后再次核对身份。
- 自定义 BA 必须读取 `WixBundleAction`。旧实现忽略 `/uninstall` 并总从首次配置页自行推断动作，导致 ARP 卸载重新进入安装界面；当前实现只在普通启动时显示 Modify 配置，Uninstall/Repair 直接进入相应确认流程。
- Bundle `MsiPackage Visible="yes"` 会让内部 MSI 与 Bundle 同时出现在 ARP。必须同时保持 `Visible="no"` 和 MSI `ARPSYSTEMCOMPONENT=1`，但不能删除 MSI registration。
- Feature 不共享组件；共享 DLL 即使内容相同也分别安装到各自目录。
- 不把 `bin`、`obj`、Publish、PDB、XML 文档或用户设置纳入 Payload。
- 编译成功不能替代 MSI 日志、注册表、Office 实际加载及完整生命周期验证。
