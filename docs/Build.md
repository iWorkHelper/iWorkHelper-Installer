# 构建与 Payload

## 先决条件

- Visual Studio 2022，按仓库根目录 `.vsconfig` 安装 `.NET 桌面开发`、`Office/SharePoint 开发`、.NET Framework 4.8 targeting pack/SDK 和 MSBuild。
- Visual Studio 扩展 **HeatWave for Visual Studio**。它提供现代 SDK-style `.wixproj` 的项目系统；WiX NuGet SDK 只能提供还原/命令行构建，不能替代 VSIX。安装路径：Visual Studio `扩展` → `管理扩展`，搜索 `HeatWave for Visual Studio`，下载后关闭所有 VS 实例完成安装并重新打开解决方案。
- .NET SDK。
- 项目所有者已确认 WiX 7 OSMF EULA/维护费适用性。
- 目标机须预先安装 .NET Framework 4.8 和 VSTO Runtime。两者均不进入 Bundle Chain；缺少时安装器只提供 Microsoft 官方页面并要求安装后重新运行。
- VSTO deployment/application manifest 必须由受信任发布证书签名。源码库不保存私钥、PFX 或证书指纹。

## 统一入口

在 `iWorkHelper-Installer` 下执行：

```powershell
$thumbprint = .\scripts\Ensure-DevelopmentCertificate.ps1
.\build.ps1 -Version 1.0.0 -ManifestCertificateThumbprint $thumbprint
```

脚本把私钥留在当前用户的 `My` 证书存储，仅把公钥证书导出到被忽略的 `.local/certificates`。若要在受控测试机实际加载 Add-in，须由使用者通过 Windows 证书管理界面明确将公钥证书加入相应的受信任根和受信任发布者存储；构建脚本不会静默修改信任策略。

默认 Outlook 使用安全的 `Release-Intranet`。明确需要在线 OCR 版时：

```powershell
.\build.ps1 -Version 1.0.0 -OutlookConfiguration Release-Internet
```

仅构建插件、收集 Payload 和运行静态验证，不触发 WiX 包还原：

```powershell
.\build.ps1 -Version 1.0.0 -SkipInstallerBuild
```

VSTO 项目系统要求签署 deployment/application manifest；它不支持把未签名清单当作等价 Release 产物。缺少 manifest 发布证书会让插件构建明确失败。若只验证安装器收集与静态检查，可在已有、已签名 Release 输出的前提下使用 `-SkipAddinBuild -SkipInstallerBuild`。

正式产物：`artifacts/iWorkHelper-Setup-<version>-x64.exe`。自定义 BA、基础 MSI 和中文 transform 均封装在 EXE 中，不需要 sidecar。内部诊断 MSI/MST 仍输出到 `artifacts`，不得脱离 EXE 作为正式发布入口或交付给普通用户。

## Visual Studio 与 Solution Build

本项目是 WiX 7 SDK-style 项目，不需要也不得安装 WiX v3 build tools 来替代 WiX 7。首次 clone 后先按上述统一入口收集 Payload 并生成基础 MSI/中文 transform；`Payload`、`artifacts`、`bin` 和 `obj` 均被刻意排除出源码库。

`iWorkHelper-Installer.slnx` 显式声明 `Release|x64`，并把 BA、MSI、Bundle 三个项目都纳入该配置。默认版本 1.0.0 的 ProductCode 在 `Directory.Build.props` 中提供，且与 `build.ps1` 的确定性计算结果一致；构建其他版本时仍必须使用 `build.ps1 -Version x.y.z`，由脚本统一生成该版本 ProductCode 和语言 transform。脚本对 MSI 与 Bundle 使用 Rebuild，因为版本/ProductCode 预处理常量和 artifacts 路径 Payload 不足以让 MSBuild 的普通增量检查可靠失效。

安装 HeatWave 后，在 Visual Studio 工具栏选择 `Release` / `x64`，再执行 `生成` → `重新生成解决方案`。若出现项目类型 GUID `930c7802-8a8c-48f9-8165-68863bccd9dd` 无法加载，说明 HeatWave 未安装或未在当前 VS 实例启用，不是 `.wixproj` 需要迁移。命令行等价验证为：

```powershell
dotnet restore .\iWorkHelper-Installer.slnx
dotnet msbuild .\iWorkHelper-Installer.slnx /t:Rebuild /m:1 /p:Configuration=Release /p:Platform=x64
```

## Payload 白名单

Excel：主程序集、application manifest、deployment manifest、VSTO Common Utilities，共 4 个文件。

Outlook：主程序集、两个 manifest、VSTO Common/Outlook Utilities，以及运行所需的 Microsoft.Bcl、System.* 与 PdfPig DLL，共 17 个文件。

不收集 PDB、XML 文档、`bin`/`obj` 整目录或 ClickOnce `publish` 目录。`.vsto` 和 `.dll.manifest` 是 VSTO 运行所需清单，虽使用 ClickOnce 清单格式，但直接来自正常 Release Build，并以 `|vstolocal` 从安装目录加载，不使用 Publish 产物或 ClickOnce 缓存安装。

## 版本与签名

- `InstallerVersion` 必须是 MSI 三段版本，并在重要安装器修改后提升。
- 构建入口从产品名和三段版本确定性生成 ProductCode；同一版本的 en-US/zh-CN MSI 必须使用同一个 ProductCode，版本提升时 ProductCode 随之改变。不得让 language transform 改写 ProductCode，否则 Burn 无法检测、修复或卸载实际产品。
- 项目文件中的 `AcceptEula=wix7` 记录项目所有者对 WiX 7 EULA 的明确接受；若适用条件变化，必须重新评估。
- `UpgradeCode` 固定；组件 GUID 固定；MajorUpgrade 自动移除旧产品。
- 正式发布前对 MSI 与最终 EXE 做 Authenticode 签名。真实证书、私钥和签名参数不得写入仓库。
- 开发构建可在本机证书存储创建自签名 VSTO manifest 证书，并临时导出到被 `.gitignore` 排除的路径。受控测试机必须信任该开发证书；正式发布时替换为受信任的 VSTO 发布证书。
- 提交或发布前必须运行敏感信息检查，覆盖内容、文件名和路径；禁止提交 Payload、artifacts、日志、证书和本机绝对路径。
