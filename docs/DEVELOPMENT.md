# iWorkHelper Installer Development

## 开发环境

- Windows 10/11。
- Visual Studio 2022 MSBuild，插件项目需 Office/SharePoint 开发 (VSTO) 工作负载。
- Inno Setup 7 (`ISCC.exe`)。
- .NET Framework 4.8 Developer Pack。
- 本机或发布环境中的 VSTO manifest 签名证书。

## 目录结构

- `installer/iWorkHelper.iss`：Inno Setup 脚本。
- `scripts/build.ps1`：一键构建入口。
- `scripts/acquire-prerequisites.ps1`：获取并校验 VSTO Runtime 前置依赖。
- `scripts/prepare-staging.ps1`：从插件 Release 输出准备 staging。
- `scripts/validate-staging.ps1`：校验 staging 文件完整性与 Variant 隔离。
- `prerequisites/`：本地前置依赖缓存，二进制 payload 不进入 Git。
- `staging/` 与 `build/`：生成目录，不进入 Git。

## 构建流程

```text
Restore dependencies
Build eWorkHelper Release
Build oWorkHelper Release-Intranet as Local
Build oWorkHelper Release-Internet as Baidu
Validate outputs
Prepare staging
Generate packaged-components manifest
Compile iWorkHelper-Setup.exe with Inno Setup 7
```

## 构建命令

首次构建或缺少 VSTO Runtime payload：

```powershell
.\scripts\build.ps1 -AcquirePrerequisites
```

常规构建：

```powershell
.\scripts\build.ps1
```

仅在已确认插件输出存在时快速重编安装器：

```powershell
.\scripts\build.ps1 -SkipPluginBuild
```

## 静默安装（必须显式传 `/COMPONENTS=`）

`[Components]` 中的 `eworkhelper` 与 `oworkhelper` 都声明为 `Types: custom`，且默认**不勾选任何组件**。因此：

- **`/VERYSILENT` 必须显式传入 `/COMPONENTS=`**。缺少该参数时两个组件都处于未选中状态，`PrepareToInstall`（以及向导界面的"下一步"校验）会直接返回"请至少选择一个要安装的插件。"并使安装失败；安装日志中会记录 `PrepareToInstall blocked: 请至少选择一个要安装的插件。`。
- 组件名为 `eworkhelper`、`oworkhelper`，多个组件用英文逗号分隔。
- 安装 oWorkHelper 时还可用 `/OWORKHELPER_VARIANT=Local|Baidu` 选择 Variant，缺省为 `Baidu`。

示例：CurrentUser + 静默安装 oWorkHelper Local：

```powershell
.\build\iWorkHelper-Setup-1.2.1.exe `
  /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART `
  /DIR="$env:LOCALAPPDATA\iWorkHelper" `
  /COMPONENTS=oworkhelper `
  /OWORKHELPER_VARIANT=Local `
  /LOG="$env:TEMP\iworkhelper-install.log"
```

同时安装两个组件：

```powershell
.\build\iWorkHelper-Setup-1.2.1.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART `
  /DIR="$env:LOCALAPPDATA\iWorkHelper" /COMPONENTS=eworkhelper,oworkhelper `
  /OWORKHELPER_VARIANT=Local /LOG="$env:TEMP\iworkhelper-install.log"
```

静默卸载：

```powershell
& "$env:LOCALAPPDATA\iWorkHelper\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

注意事项：

- 静默安装同样会执行 Office Host 检测、Office x86/x64 架构检测与 .NET Framework 4.8 检测；任一项不满足都会中止安装，具体原因写入 `/LOG=` 指定的日志。
- 静默模式下不会有交互提示，因此建议始终配合 `/SUPPRESSMSGBOXES` 与 `/LOG=` 使用。
- 升级时如果取消勾选某个组件，安装器会在 `ssPostInstall` 阶段删除该组件的注册项（`Software\Microsoft\Office\<Host>\Addins\<AddinId>`）与 `{app}\<Component>` 目录；升级验证时请确认被取消勾选的插件不再被 Office 加载。

## 前置依赖规则

`prerequisites/vstor_redist.exe` 必须来自 Microsoft 官方下载地址，并通过以下校验：

- Windows PE payload。
- Authenticode 签名有效，发布者为 Microsoft。
- VSTO Runtime 10.0.60917 版本族。
- 文件大小、SHA-256 与 `prerequisites.lock.json` 一致。

## 开发约束

- 不打包 `bin/Debug`。
- 不提交 `build/`、`staging/`、`vstor_redist.exe`、日志、证书或本地配置。
- 不在安装器内收集或保存 Baidu AK/SK/API Key/Secret Key。
- 修改注册、信任、Variant 或升级身份时必须同步更新架构和发布文档。

## 安装检测、升级与测试

安装器启动时使用固定 AppId `{9B51BBD1-03A5-4AE0-9B0E-58C8B7B5E8C1}` 检查官方卸载记录，并与 `Software\\iWorkHelper\\Installer` 元数据核对。首次安装使用 `DefaultDirName`；已有有效记录时目录页预填原路径。升级和修复锁定该路径及原安装范围，避免产生第二条卸载记录。

版本比较使用数字组件比较，不使用字符串排序。低版本升级、同版本修复，高版本安装包默认阻止降级；记录损坏、多个记录或目录不存在时不自动覆盖。

oWorkHelper 的 `OWorkHelperVariant` 会从元数据继承；首次安装仍默认 `Baidu`。切换 Variant 只替换安装器管理的程序文件，不删除 `%AppData%\\iWorkHelper`、`user.config` 或 OCR 凭据。升级前会保存关键注册信息，验证失败时恢复注册表检查点；文件层回滚由 Inno Setup 提供，详见架构和故障排查文档。

可运行纯策略自动化测试：

```powershell
.\\scripts\\test-installer-state.ps1
```

该脚本覆盖版本比较、首次安装、修复、升级、降级阻止和不一致记录阻止。真实安装、Office/VSTO 加载、Outlook 占用、卸载和用户配置保留必须在 disposable Windows/Office 环境中验证，不能用脚本模拟后标记为通过。
