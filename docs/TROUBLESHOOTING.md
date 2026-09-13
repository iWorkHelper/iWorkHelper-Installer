# iWorkHelper Installer Troubleshooting

## Office Host 未检测到

问题：安装组件时提示未检测到 Excel 或 Outlook。

原因：安装器通过 App Paths 等注册表信息判断宿主是否存在。

处理：确认已安装桌面版 Microsoft Office，并且目标 Host 可正常启动。Office 网页版或仅安装部分组件不满足 VSTO 加载条件。

## Office 架构无法可靠识别

问题：安装器提示无法可靠识别 Office x86/x64 架构。

原因：ClickToRun 平台信息缺失或检测结果冲突。

处理：不要根据 Windows 位数手工绕过；应补充检测证据后再调整安装器逻辑。

## VSTO Runtime 缺失或损坏

问题：目标电脑缺少 VSTO Runtime 或 `VSTOInstaller.exe`。

处理：安装器会使用内置 Microsoft 官方 `vstor_redist.exe` 自动安装或修复，并二次验证。构建时必须确保 payload 和 lock 文件校验通过。

## 加载项未显示 Ribbon

已确认经验：COMAddIns 自动化探测不一定能作为 VSTO 加载的唯一判断。判断加载状态应结合注册表、Manifest URI、VSTO Loader 日志、Office Resiliency 状态和实际 Ribbon 显示。

## Outlook DisabledItems / CrashingAddinList

Outlook 可能因启动性能或历史崩溃记录禁用加载项。处理时只能精确清理与本安装项相关的测试残留，不应清空整个 Resiliency 配置。

## 生产信任未完成

当前安装包仍为 Development/Test 信任策略。生产发布前必须替换为正式证书和受控信任方案，并完成目标环境矩阵验证。

## 已验证结论

- Inno Setup 7.1.0 编译链路可生成单一 Setup EXE。
- CurrentUser 双组件安装、注册表验证与卸载路径曾通过本机验证。
- eWorkHelper 与 oWorkHelper 均曾确认可由 Office Host 实际加载并显示 Ribbon。
- AllUsers、UAC、Office x86/x64 完整矩阵仍需实机验证。
