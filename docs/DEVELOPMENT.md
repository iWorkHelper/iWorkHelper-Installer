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
