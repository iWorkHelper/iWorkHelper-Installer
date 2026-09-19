# iWorkHelper Installer Release

## 当前版本

当前安装器产品版本：`1.3.0`。

安装器文件版本等必须为四段数值格式时使用 `1.3.0.0`。默认输出：

```text
build/iWorkHelper-Setup-1.3.0.exe
```

## 版本来源

| 项目 | 来源 |
| --- | --- |
| InstallerVersion | `scripts/build.ps1` 参数，默认 `1.3.0` |
| InstallerFileVersion | 由产品版本派生，默认 `1.3.0.0` |
| eWorkHelperVersion | eWorkHelper `AssemblyInformationalVersion` |
| oWorkHelperVersion | oWorkHelper `AssemblyInformationalVersion` |

## 打包输入

| 组件 | 配置 | 来源 |
| --- | --- | --- |
| eWorkHelper | `Release|Any CPU` | `../eWorkHelper/bin/Release` |
| oWorkHelper Local | `Release-Intranet|Any CPU` | `../oWorkHelper/bin/Release-Intranet` |
| oWorkHelper Baidu | `Release-Internet|Any CPU` | `../oWorkHelper/bin/Release-Internet` |

## 静默安装（发布验证）

`eworkhelper` 与 `oworkhelper` 均为 `Types: custom` 且默认不勾选，因此**静默安装必须显式传 `/COMPONENTS=`**：`/VERYSILENT` 不带该参数时两个组件都未选中，安装会在 `PrepareToInstall` 阶段以"请至少选择一个要安装的插件。"中止（日志中出现 `PrepareToInstall blocked:`）。

标准发布验证命令（CurrentUser，安装 oWorkHelper Local，隔离目录 + 日志）：

```powershell
build\iWorkHelper-Setup-1.3.0.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART `
  /DIR="$env:TEMP\iworkhelper-verify" /COMPONENTS=oworkhelper `
  /OWORKHELPER_VARIANT=Local /LOG="$env:TEMP\iworkhelper-install.log"
```

随后静默卸载并检查残留：

```powershell
& "$env:TEMP\iworkhelper-verify\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

验证要点：

- `/COMPONENTS=` 可写多个组件（英文逗号分隔），`/OWORKHELPER_VARIANT=Local|Baidu` 选择 Variant（缺省 `Baidu`）。
- 静默安装仍会执行 Office Host / Office 架构 / .NET Framework 4.8 检测，失败原因写入 `/LOG=` 日志。
- 升级场景中如取消勾选某个组件，安装器会在 `ssPostInstall` 阶段删除该组件的注册项与 `{app}` 下对应子目录。

## 发布前检查

- 插件 Release 构建均为 0 Error / 0 Warning。
- `OfflineTester --selftest` 通过。
- `scripts/build.ps1` 完整构建通过。
- `staging` 通过 `.vsto`、`.dll.manifest`、主 DLL 和依赖完整性校验。
- Local 与 Baidu Variant 主 DLL hash 不应相同。
- `packaged-components.json` 不包含私钥、密码或本机绝对路径。
- `.gitignore` 覆盖生成目录、前置依赖 payload、日志、缓存、证书和本地配置。

## 变更记录

### v1.3.0

- 更新 eWorkHelper、oWorkHelper 与统一安装器版本至 `1.3.0`。
- 安装器文件版本为 `1.3.0.0`，默认输出 `iWorkHelper-Setup-1.3.0.exe`。

### v1.2.1

- 更新 eWorkHelper、oWorkHelper 与统一安装器版本至 `1.2.1`。
- 安装器文件版本为 `1.2.1.0`，默认输出 `iWorkHelper-Setup-1.2.1.exe`。

### v1.2.0

- 统一安装器版本为 `1.2.0`，文件版本使用 `1.2.0.0`。
- 默认输出 `iWorkHelper-Setup-1.2.0.exe`。
- 保留 eWorkHelper 与 oWorkHelper 双组件安装，oWorkHelper 默认 Variant 为 Baidu。
- VSTO Runtime 前置依赖支持本地校验和安装/修复。
- 精简 docs，合并阶段验证和诊断记录为长期维护文档。
- 补充静默安装必须显式传 `/COMPONENTS=` 的约束与发布验证命令（见"静默安装（发布验证）"）。
- 修复安装向导语言、VSTO 前置包退出码、Manifest URI 转义、升级取消勾选组件残留、Office 运行检测与诊断脚本注册表路径等问题，详见 `CHANGELOG.md` 与 `docs/REVIEW_TRACKING.md`。
