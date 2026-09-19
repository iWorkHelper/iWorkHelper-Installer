# iWorkHelper Installer

`iWorkHelper-Installer` 是 iWorkHelper 统一安装程序项目，用于部署现有的 Excel VSTO 插件 `eWorkHelper` 与 Outlook VSTO 插件 `oWorkHelper`。

当前稳定版本：`1.2.1`。

## 目标产物

```text
iWorkHelper-Setup-1.2.1.exe
```

安装程序设计为单一 Windows 原生安装向导，支持：

- 选择安装 `eWorkHelper`、`oWorkHelper` 或二者同时安装。
- 选择 `CurrentUser` 或 `AllUsers` 安装范围。
- 自定义 `iWorkHelper` 根安装目录。
- 检测实际 Office Host 与 Office x86/x64 架构。
- 自动检测并在缺失、版本不足或损坏时安装/修复 VSTO Runtime。
- 写入对应 VSTO Add-in 注册项。
- 卸载、维护安装与后续升级。

## 安装

请从 [GitHub Releases](https://github.com/iWorkHelper/iWorkHelper-Installer/releases) 下载：

下载后双击运行安装向导，按需选择 Excel 插件 `eWorkHelper`、Outlook 插件 `oWorkHelper`、安装范围和安装目录。

## 构建

### 构建前置条件

| 前置条件 | 说明 |
| --- | --- |
| Inno Setup 7 | 需要 `ISCC.exe`。默认搜索路径包含 `%ProgramFiles%\Inno Setup 7`、`%LOCALAPPDATA%\Programs\Inno Setup 7` 与 `PATH`。 |
| Visual Studio 2022 MSBuild | 需安装 Office/SharePoint 开发 (VSTO) 工作负载；使用 `%ProgramFiles%\Microsoft Visual Studio\2022\<Edition>\MSBuild\Current\Bin\MSBuild.exe`。 |
| .NET Framework 4.8 Developer Pack | 插件项目目标框架。 |
| VSTO 清单签名证书 | 证书存储（`CurrentUser\My` 或 `LocalMachine\My`）中需存在含私钥的清单签名证书（例如开发证书 `CN=iWorkHelper Development Manifest Signing`）；也可通过环境变量 `IWORKHELPER_MANIFEST_CERT_THUMBPRINT` 显式指定指纹。构建脚本会自动查找，找不到则直接失败。 |
| `prerequisites\vstor_redist.exe` | Microsoft 官方 VSTO Runtime 前置包，作为离线安装 payload 被内嵌。文件缺失时先执行 `.\scripts\build.ps1 -AcquirePrerequisites`。 |

一键构建入口：

```powershell
.\scripts\build.ps1
```

首次构建或本机缺少 VSTO Runtime prerequisite 时，先执行：

```powershell
.\scripts\build.ps1 -AcquirePrerequisites
```

该命令会从 Microsoft 官方 `download.microsoft.com` 获取 `prerequisites\vstor_redist.exe`，验证 Authenticode 签名、Microsoft 发布者、VSTO Runtime 10.0.60917 版本、PE 文件头、文件大小和 SHA-256，并写入 `prerequisites\prerequisites.lock.json`。`vstor_redist.exe` 是本地构建依赖，不进入 Git；最终安装 EXE 会内嵌它以支持目标电脑离线安装。

输出：

```text
build\iWorkHelper-Setup-<InstallerVersion>.exe
build\packaged-components.json
```

默认打包：

- `eWorkHelper Release`
- `oWorkHelper Local`：仅本地 OCR，对应 `Release-Intranet`
- `oWorkHelper Baidu`：本地 + Baidu OCR，对应 `Release-Internet`

安装 oWorkHelper 时默认选择 `Baidu`。安装器不收集或保存 Baidu AK/SK/API Key/Secret Key；在线 OCR 凭据仍由 oWorkHelper 自身设置页配置。

## 静默安装

两个组件都属于自定义类型且默认不勾选，因此**静默安装必须显式传入 `/COMPONENTS=`**；缺少该参数时不会有任何组件被选中，安装会直接中止。

```powershell
iWorkHelper-Setup-1.2.1.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART `
  /DIR="$env:LOCALAPPDATA\iWorkHelper" /COMPONENTS=oworkhelper `
  /OWORKHELPER_VARIANT=Local /LOG="$env:TEMP\iworkhelper-install.log"
```

组件名：`eworkhelper`、`oworkhelper`（多个用英文逗号分隔）；`/OWORKHELPER_VARIANT` 取 `Local` 或 `Baidu`，缺省 `Baidu`。详见 [Development](docs/DEVELOPMENT.md)。

当前安装器注册元数据仍标记为 `Development/Test` 信任策略。公开发布前如需企业级信任链，应替换为正式代码签名/清单签名策略，并完成目标环境矩阵验证。

## 技术路线

当前技术路线：使用 Inno Setup 7 作为 Installer Engine。

详见：

- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Requirements](docs/REQUIREMENTS.md)
- [Release](docs/RELEASE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## 重要约束

- Installer 项目不得为了部署便利修改 `../eWorkHelper` 或 `../oWorkHelper` 的业务代码、命名空间、程序集名、GUID 或目标框架。
- 正式发布不能使用开发清单证书 `CN=iWorkHelper Development Manifest Signing` 作为生产信任方案。
- 不得仅根据 Windows 位数推断 Office 位数。
- 正常 Windows + Office 环境下不重复安装已满足要求的 Runtime；VSTO Runtime 缺失、版本不足或损坏时由安装器使用内置 Microsoft 官方 `vstor_redist.exe` 自动补齐。

## License

License: [MIT](LICENSE)
