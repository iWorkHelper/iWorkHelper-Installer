# iWorkHelper Installer Requirements

本文档记录统一安装程序的长期需求基线。当前实现采用 Inno Setup 7 生成统一安装包。

## 目标

统一安装程序用于部署现有两个 VSTO 插件：

| 组件 | Office Host | 现有项目 |
| --- | --- | --- |
| eWorkHelper | Excel | `../eWorkHelper/eWorkhelper.csproj` |
| oWorkHelper | Outlook | `../oWorkHelper/oWorkhelper.vbproj` |

安装程序最终应生成独立 Windows 安装包，例如 `iWorkHelper-Setup.exe`，允许用户选择安装 eWorkHelper、oWorkHelper 或二者同时安装。

## 安装能力要求

- 支持组件选择：`eWorkHelper`、`oWorkHelper` 可独立选择。
- 支持安装目录自定义，目录应以 `iWorkHelper` 为根，组件分别进入子目录。
- 支持安装范围：`CurrentUser` 与 `AllUsers`。
- `CurrentUser` 默认不要求管理员权限。
- `AllUsers` 需要管理员权限。
- 安装程序必须检测实际 Office 位数，不能仅根据 Windows 位数推断注册表视图。
- 缺少 Excel 时不得安装 eWorkHelper。
- 缺少 Outlook 时不得安装 oWorkHelper。
- 安装后应写入 VSTO Add-in 注册项，并使对应 Office 应用启动时加载插件。
- 支持卸载、重新安装、后续升级和注册表清理。

## 运行环境原则

目标系统为 Windows 10 及以后版本，目标 Office 组合包括：

- 32-bit Windows + 32-bit Office
- 64-bit Windows + 32-bit Office
- 64-bit Windows + 64-bit Office

安装程序自身不应依赖用户额外安装 .NET Desktop Runtime、VC++ Runtime、Node.js、Python、Java、Electron 或 WebView。

现有 VSTO 插件可依赖正常 Office 环境通常具备或可检测的组件：

- Microsoft Office 桌面版
- .NET Framework 4.8
- Visual Studio 2010 Tools for Office Runtime 4.0
- Office Primary Interop Assemblies 或 Embedded Interop Types 对应能力

M0 审计显示两个插件均使用 Embedded Interop Types，因此安装器不应把 Office PIA 作为默认额外安装项。

## 检测优先策略

安装程序应遵循：

1. 检测 Office、Host 应用、Office 位数、.NET Framework、VSTO Runtime。
2. 正常环境直接部署插件文件并注册。
3. 仅在确认为缺失且插件无法运行时，才提示或执行兜底处理。
4. 不默认捆绑或安装与插件无关的运行库。

## 技术路线约束

当前技术路线为 Inno Setup 7。安装器脚本负责组件选择、安装范围、Office Host 检测、Office 位数检测、VSTO Runtime 检测、文件部署、VSTO 注册和卸载清理。

如果后续发现 Inno Setup 无法可靠覆盖新的升级、回滚或企业部署需求，应在架构文档中说明限制并重新评估 WiX/MSI/Burn 等替代方案。

## 已识别的部署注意事项

- 生产发布需要可信签名策略。现有构建输出使用 `CN=iWorkHelper Development Manifest Signing` 开发清单证书签名，不能视为生产可信证书。
- eWorkHelper 与 oWorkHelper 项目文件不保存 PFX、私钥或固定证书指纹。正式构建必须通过受保护证书存储、环境变量或 MSBuild 参数提供清单签名配置。
- 现有发布说明明确编译组件包不是可直接双击安装包；统一安装程序必须承担文件部署、注册表写入和信任处理。
- 当前仅存在本机生成输出，尚未在目标 Windows/Office 矩阵中完成真实安装验证。

## 参考资料

- Microsoft Learn: Registry entries for VSTO Add-ins
- Microsoft Learn: Deploying a VSTO Solution Using Windows Installer
