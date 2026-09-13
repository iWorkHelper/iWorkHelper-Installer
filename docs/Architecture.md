# iWorkHelper Installer Architecture

## 目标

iWorkHelper Installer 是统一 Windows 安装程序，用于部署 Excel VSTO 插件 `eWorkHelper` 与 Outlook VSTO 插件 `oWorkHelper`。安装器支持选择组件、安装范围、安装目录、Office Host 检测、Office 架构检测、VSTO Runtime 补齐、VSTO 注册和卸载清理。

## 技术路线

- Installer Engine：Inno Setup 7。
- 输入组件来自相邻仓库的发布输出，不从 `bin/Debug` 打包。
- 安装器项目不得修改插件业务代码、命名空间、程序集名、GUID 或目标框架。
- 安装包当前为 `Development/Test` 信任策略；生产发布需要正式签名与目标环境验证。

## 产品模型

- `eWorkHelper`：Excel VSTO Add-in。
- `oWorkHelper`：Outlook VSTO Add-in。
- `oWorkHelper` 安装时只能选择一个 Variant：`Local` 或 `Baidu`。
- 默认 Variant：`Baidu`，即本地识别 + Baidu OCR 能力；凭据仍由 oWorkHelper 设置页管理。

## 支持范围

- Windows 10/11。
- Microsoft Excel / Outlook 桌面版。
- Office x86 / x64 需通过 Office 检测结果决定注册表视图，不根据 Windows 位数直接推断。
- .NET Framework 4.8。
- VSTO Runtime 4.0。

## 注册与加载模型

- CurrentUser 使用 `HKCU\Software\Microsoft\Office\<Host>\Addins\<AddinId>`。
- AllUsers 根据 Office 架构写入 `HKLM32` 或 `HKLM64` 对应视图。
- Manifest 使用本地 `file:///...|vstolocal` URI。
- `LoadBehavior=3`，不使用 RegAsm。
- 安装后写入 metadata：安装器版本、范围、路径、组件、插件版本、Office 架构、Registry View、Trust Mode 和 oWorkHelper Variant。

## 信任与签名

- 开发/测试可使用受控测试证书完成 VSTO 加载验证。
- 源码和仓库不得包含 PFX、私钥、证书密码、证书指纹或本机证书路径。
- 生产发布需要正式代码签名证书和最小信任策略。
- 正式发布不得依赖降低全局 Office 安全设置。

## 升级身份

- `AppName=iWorkHelper`。
- `AppId={{9B51BBD1-03A5-4AE0-9B0E-58C8B7B5E8C1}` 固定不随版本、组件或 Variant 变化。
- Local/Baidu 当前不支持同机并存；如未来要求并存，需要设计新的产品身份。
