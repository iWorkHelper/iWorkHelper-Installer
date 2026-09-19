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

## 诊断脚本报告"未找到"但安装实际成功

诊断脚本 `tools\OutlookResiliency\check_iworkhelper_addin_registration.ps1`（位于 `../oWorkHelper`）早期版本只检查 `Software\Microsoft\Office\16.0\<Host>\Addins`，而本安装器写入的是**无版本段**的 `Software\Microsoft\Office\<Host>\Addins\<AddinId>`（`AddinId` 为 `oWorkhelper` / `eWorkhelper`），因此安装成功后脚本也会显示"Path not found"。

修复后脚本同时检查：

- `HKCU` / `HKLM` 两个根；
- `Software\Microsoft\Office\<Host>\Addins`（无版本段，安装器实际写入位置）与 `Software\Microsoft\Office\16.0\<Host>\Addins`；
- 原生视图与 `Software\WOW6432Node\...`（32 位）视图；
- 键名匹配 `oWorkhelper` 与 `eWorkhelper`（以及 `iWorkHelper` / `ThisAddIn`）。

排查时请先确认使用的是修复后的脚本；若 `Addins (version-agnostic, written by iWorkHelper installer)` 段落中能读到 `Manifest` 与 `LoadBehavior: 3`，说明注册项已写入。

## Outlook DisabledItems / CrashingAddinList

Outlook 可能因启动性能或历史崩溃记录禁用加载项。处理时只能精确清理与本安装项相关的测试残留，不应清空整个 Resiliency 配置。

## 生产信任未完成

当前安装包仍为 Development/Test 信任策略。生产发布前必须替换为正式证书和受控信任方案，并完成目标环境矩阵验证。

## 升级被阻止

安装器会读取固定 AppId 的 Inno 卸载记录和 `Software\\iWorkHelper\\Installer` 元数据。若发现多个记录、路径不存在、记录路径与卸载记录不一致、版本无法解析或当前安装包低于已安装版本，会阻止自动覆盖。这是为了避免误覆盖其他 Office 插件或产生重复卸载项；确认旧安装已损坏时，应先使用对应卸载程序清理，再重新安装。

升级/修复不支持直接改安装目录。目录页显示原路径且路径被锁定；需要迁移到新目录时，先卸载再重新安装。升级前 Outlook/Excel 仍需关闭，文件被占用、权限不足或 VSTO 注册失败时安装会失败并保留错误日志。

失败恢复包括关键安装元数据和 VSTO Manifest 注册的进程内检查点，以及 Inno Setup 的文件回滚。若系统重启、磁盘故障或第三方程序长期锁定文件导致安装器自身无法完成回滚，不能保证事务型恢复；请关闭 Office 后重新运行相同版本安装包或先卸载后安装。用户配置和 OCR 凭据位于用户数据目录，不由升级删除。

## 已验证结论

- Inno Setup 7.1.0 编译链路可生成单一 Setup EXE。
- CurrentUser 双组件安装、注册表验证与卸载路径曾通过本机验证。
- eWorkHelper 与 oWorkHelper 均曾确认可由 Office Host 实际加载并显示 Ribbon。
- AllUsers、UAC、Office x86/x64 完整矩阵仍需实机验证。
