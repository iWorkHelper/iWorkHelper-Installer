# iWorkHelper Installer

iWorkHelper Installer 是面向 Windows x64 的统一安装器源码，为 eWorkHelper（Excel VSTO）与 oWorkHelper（Outlook VSTO）提供单一 EXE 入口、可选功能、双安装范围和中英文界面。

## 主要功能

- 使用 WiX Toolset 构建统一 Burn Bundle 与 MSI。
- 支持按当前用户或所有用户安装。
- 支持独立选择 Excel、Outlook 或两个加载项。
- 支持简体中文与英文安装界面。
- 检测 Windows、Office x64、.NET Framework 4.8 和 VSTO Runtime 前置条件。
- 支持安装、修改、修复、卸载与主版本升级流程。

## 技术栈与支持环境

- WiX Toolset 7、Burn、MSI。
- C# / .NET Framework 4.8 自定义 Bootstrapper Application。
- Windows 10 1809+ 或 Windows 11 x64。
- Microsoft Office 2016+ x64。
- Visual Studio 2022；在 IDE 中加载 WiX 项目时需要 HeatWave 扩展。

## 构建

构建前应先在同级目录准备 eWorkHelper 与 oWorkHelper 的 Release 输出。正式 VSTO 清单需要受信任证书签名；证书、指纹文件和其他本机签名材料不得提交到 Git。

```powershell
dotnet tool restore
dotnet restore .\iWorkHelper-Installer.slnx
.\build.ps1
```

构建脚本负责收集精确 Payload、构建本地化 MSI 和 Bundle，并执行适用的静态验证。可用参数、输出位置和证书要求见 [构建文档](docs/Build.md)。

## 测试

```powershell
.\tests\Test-InstallerSources.ps1
```

自动构建与数据库检查不能替代真实安装生命周期验证。发布前应在干净的 Windows x64 环境中覆盖 Excel only、Outlook only、Both、per-user、per-machine、Modify、Repair、Remove 与 Upgrade。

## 项目结构

```text
BootstrapperApplication/  自定义安装界面与 Burn 生命周期
Bundle/                   Bundle Chain、搜索与入口定义
MSI/                      MSI Package、Feature 与 VSTO 注册
Localization/             中英文资源
Payload/                  构建时收集的加载项文件（不提交产物）
scripts/                  Payload、证书与开发环境辅助脚本
tests/                    源码、Bundle 与 MSI 自动检查
docs/                     架构、构建、测试和维护文档
```

## 开发状态

源码、CLI 构建、MSI/Bundle 静态检查及主要安装范围流程已有验证记录；目标 Office 组合、升级路径和 IDE 加载仍应按 [测试文档](docs/Testing.md) 与 [已知问题](docs/KnownIssues.md) 持续验证。

## 文档

从 [文档索引](docs/README.md) 开始。修改安装器行为时，应同步维护需求、架构、生命周期、注册、构建和测试说明。

## License

当前仓库未包含独立 License 文件。提交或公开发布前，应确认其许可证与两个加载项项目及发布策略一致。
