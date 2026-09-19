# iWorkHelper-Installer 审查发现修复跟踪

来源：`CODE_REVIEW_2026-09-13.md`（工作区根目录审查报告）
建立日期：2026-09-13
提交策略：**不提交 git**，改动保留在工作树。

## 状态说明

| 状态 | 含义 |
|---|---|
| 待修复 | 尚未开始 |
| 修复中 | 正在处理 |
| 已修复 | 代码已改，尚未验证 |
| 已验证 | 已通过编译/打包验证并记录结论 |
| 需真机验证 | 本机无法闭环，需指定环境人工验证 |
| 不适用 | 经复核确认为非缺陷，已说明原因 |

## 验证方式

- 端到端：`pwsh -File scripts\build.ps1` 必须 `BUILD SUCCESS` 并产出 `build\iWorkHelper-Setup-1.2.0.exe`。
- 静默安装验证（隔离目录，验证后删除）：
  `iWorkHelper-Setup-1.2.0.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="<临时目录>" /COMPONENTS=oworkhelper /OWORKHELPER_VARIANT=Local /LOG="<临时日志>"`
  随后用 `unins000.exe /VERYSILENT` 卸载并确认注册表与目录被清理。
- 本机环境：Windows 10.0.26200 x64，Office x64（16.0.20326.20132），Inno Setup 7.1.0。

### 本次会话（2026-09-13）实际执行的验证

| 验证 | 范围 | 结果 |
|---|---|---|
| ISCC 单独编译 `.iss` | `installer\iWorkHelper.iss` | **成功**（见下方"编译验证记录"） |
| FileUri 隔离运行测试 | I-04，9 条路径 + 2 项定点检查 | **9/9 + 2/2 PASS** |
| `build.ps1` 锁文件校验隔离测试 | I-10，1 正例 + 4 负例 | **全部通过**（负例仍被拒绝） |
| 诊断脚本修复前/后对照运行 | I-09 | **修复前复现假阴性，修复后命中 `oWorkhelper`** |
| `pwsh -File scripts\build.ps1` 完整构建 | 端到端 | **未执行**（见下方说明） |
| 安装器静默安装/卸载实跑 | I-03/I-06/I-08 端到端 | **未执行**（见下方说明） |

未执行 `scripts\build.ps1` 完整构建的原因：该脚本会 `Rebuild` 兄弟仓库 `eWorkHelper`/`oWorkHelper`，而本会话期间另有代理正在并发修改 `oWorkHelper`，此时全量重建可能因与本任务无关的原因失败。按约束改用 ISCC 单独编译验证 `.iss`（即上方已验证项）。

未执行安装器实跑与卸载的原因：本机 `HKCU\Software\Microsoft\Office\Outlook\Addins\oWorkhelper` 已存在开发环境注册项（指向 `oWorkHelper\bin\Release-Intranet`），`CurUninstallStepChanged` 会删除 HKCU/HKLM32/HKLM64 下的同名键，实跑安装+卸载会破坏该既有状态；静默安装"不带 `/COMPONENTS=`"的失败路径同理未实跑。相关内容只按脚本逻辑陈述，未写入任何实测结论。

### 编译验证记录

命令（工作目录 `C:\Users\Yang\Documents\github\iWorkhelper\iWorkHelper-Installer`）：

```powershell
& "C:\Users\Yang\AppData\Local\Programs\Inno Setup 7\ISCC.exe" `
  "/DInstallerVersion=1.2.0" "/DInstallerFileVersion=1.2.0.0" `
  "/DEWorkHelperVersion=1.2.0" "/DOWorkHelperVersion=1.2.0" `
  "/DOWorkHelperLocalVersion=1.2.0" "/DOWorkHelperBaiduVersion=1.2.0" `
  installer\iWorkHelper.iss
```

结果：**`Successful compile`，退出码 `0`**（全部编辑完成后的最终编译：10.703 sec；首次编译 22.594 sec）。产出 `C:\Users\Yang\Documents\github\iWorkhelper\iWorkHelper-Installer\build\iWorkHelper-Setup-1.2.0.exe`（44,034,454 字节）。日志中 `Parsing [Languages] section` 后输出 `Reading file: C:\Users\Yang\AppData\Local\Programs\Inno Setup 7\Languages\ChineseSimplified.isl`。`staging\` 已存在，未重新生成。

---

## 高

### I-01 安装向导界面语言实际是英文（`Default.isl`）
- **位置**：`installer\iWorkHelper.iss:47`
- **证据**：`[Languages] Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"`；实测 `Default.isl` 的 `LanguageName=English`，向导内置串为 `Setup` / `Welcome to the [name] Setup Wizard` / `&Next >`。而 `[Code]` 自定义消息为中文 → 界面中英混杂。Inno Setup 7 自带 `Languages\ChineseSimplified.isl`。
- **方案**：改为 `MessagesFile: "compiler:Languages\ChineseSimplified.isl"`。
- **状态**：已验证
- **验证证据**：
  - `.iss:47` 现为 `Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"`。
  - ISCC 7.1.0 编译日志按该路径读取 `...\Inno Setup 7\Languages\ChineseSimplified.isl`（路径不存在时 ISCC 会直接报错中止），编译退出码 0。
  - 该 `.isl` 中 `LanguageName=简体中文`、`LanguageID=$0804`、`LanguageCodePage=936`；原 `Default.isl` 为 `LanguageName=English`。
  - 说明：未实际启动向导逐页目视确认渲染语言（本会话未运行安装器），结论依据为编译期消息文件解析路径与 `.isl` 身份字段。

### I-02 CurrentUser 注册表视图未按 Office 架构显式指定（需真机验证）
- **位置**：`installer\iWorkHelper.iss:637-646`（`RegistryRootForInstall`）+ `:34` `PrivilegesRequired=lowest` + `:33` `ArchitecturesInstallIn64BitMode=x64compatible`
- **问题**：HKLM 分支正确使用显式 `HKLM32`/`HKLM64`；CurrentUser 分支使用裸 `HKCU`（64 位安装模式下指向 64 位视图），从不使用 `HKCU32`。项目自带诊断脚本却同时检查 `HKCU\Software\WOW6432Node\...`。
- **风险**：非管理员安装 + **32 位 Office** 时可能注册到 32 位 Office 不读取的视图，导致加载项不加载。
- **测试覆盖**：`build\*.log` 共 13 份安装/卸载日志，**Office 架构全部为 x64，x86 出现 0 次**，该路径从未真机验证。
- **方案**：本机（x64 Office）无法闭环，保持 **需真机验证**；若确认有问题，CurrentUser 也改为按 `OfficeArchitecture` 选择 `HKCU32`/`HKCU64`，与 HKLM 分支对齐。
- **状态**：需真机验证
- **必须在何种机器上验证（明确要求）**：
  1. **机器 A**：Windows 10/11 **x64** + **32 位（x86）Microsoft Office/VSTO 宿主**，使用**非管理员**账户（触发 `PrivilegesRequired=lowest` → `HKCU` 分支）。
  2. **机器 B**（回归对照）：x64 机器 + **64 位 Office**，非管理员账户（确认改动前后行为不变）。
  3. 可选：x86 Windows（32 位系统）无法提供 x64 Office，仅用于确认 `IsWin64=False` 分支。
- **验证步骤**：
  1. 记录 `Outlook.exe`/`EXCEL.EXE` 位数（任务管理器或 `Get-Process` 的 WOW64/路径判断）与 `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration\Platform`。
  2. 执行 `iWorkHelper-Setup-1.2.0.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="%LOCALAPPDATA%\iWorkHelper" /COMPONENTS=oworkhelper /OWORKHELPER_VARIANT=Local /LOG="%TEMP%\iw-x86.log"`。
  3. 用修复后的 `check_iworkhelper_addin_registration.ps1` 确认注册项实际落在哪个视图：`HKCU\Software\Microsoft\Office\Outlook\Addins\oWorkhelper`（64 位视图）与 `HKCU\Software\WOW6432Node\Microsoft\Office\Outlook\Addins\oWorkhelper`（32 位视图）分别是否存在。
  4. 启动 32 位 Outlook，确认 `oWorkhelper` 出现在"COM 加载项"且 Ribbon 实际显示（`LoadBehavior=3`）。
- **期望结果**：32 位 Office + 非管理员场景下，注册项必须落在 32 位 Office 读取的视图，加载项可加载。若注册项只出现在 64 位视图且 32 位 Outlook 不加载，则 I-02 成立，需把 CurrentUser 分支改为按 `OfficeArchitecture` 返回 `HKCU32`/`HKCU64`。
- **判定记录要求**：记录 Outlook 位数、实际注册表视图（含 `WOW6432Node` 是否存在）、`LoadBehavior`、Ribbon 是否显示。

## 中

### I-03 升级时取消勾选的组件不会被注销，文件也不删除
- **位置**：`installer\iWorkHelper.iss:52-61`（`[Files]`）、`:811-825`（`CurStepChanged`）、`:58-61`（`[UninstallDelete]`）
- **问题**：`CurStepChanged` 只"新增"注册项；若用户上次装了 oWorkHelper、本次只勾 eWorkHelper，旧注册项与 `{app}\oWorkHelper` 文件均残留 → **被取消勾选的插件仍被 Office 加载**。
- **方案**：安装阶段检测并清理未选中组件的注册表项与目录。
- **状态**：已修复
- **实现**：
  - 新增 `DeleteAddinKey(Root, Host, AddinId)`；`DeleteAddinRoots(Root)` 改为调用它，并**仍仅在卸载路径**删除共享 `MetadataSubkey`。
  - 新增 `RemoveUnselectedComponentRegistration(Host, AddinId, ComponentName)`：对 `HKCU`、`HKLM32`、`HKLM64`（`IsWin64` 时）删除 `Software\Microsoft\Office\<Host>\Addins\<AddinId>`。不触碰元数据子键。
  - 新增 `RemoveUnselectedComponentFiles(SubDir, ComponentName)`：`DirExists` 时 `DelTree('{app}\<SubDir>', True, True, True)`，失败仅告警并写日志。
  - 新增 `CleanupUnselectedComponents()`，在 `CurStepChanged(ssPostInstall)` 首行调用（早于 `RegisterAddin`/`WriteMetadata`/`VerifyInstall`）。
  - `WriteMetadata()` 原有逻辑继续负责删除选中状态变化时的 `OWorkHelperVariant` 值。
  - **未**添加 `[InstallDelete]` 条目：注册表清理必须走 `[Code]`，把注册表与文件处理集中在同一处更易审计；`[InstallDelete]` 也无法表达"组件未被选中"这一条件。
- **验证证据**：ISCC 编译通过（`CleanupUnselectedComponents` 及新过程均参与 `Compiling [Code] section`）。
- **代码复核（复查者补充）**：调用顺序正确——`CleanupUnselectedComponents()` 在 `ssPostInstall` 首行、`RegisterAddin` 之前，且每个分支都被 `if not Selected…` 守卫，因此**不会删除本次选中组件的注册项**；`MetadataSubkey` 仅在卸载路径删除（`:753`），选中组件的元数据得以保留；对全新安装（无旧注册）为 no-op（`DirExists` 为假）。
- **残留风险（低，需知晓）**：`RemoveUnselectedComponentRegistration` 会无条件尝试删除 `HKCU`、`HKLM32`、`HKLM64` 三处同名键，**不区分安装范围**。非管理员安装时 HKLM 删除会静默失败（返回值被忽略，无副作用）；但**管理员以 `/CURRENTUSER` 安装并取消勾选某组件时，会一并删除该组件的机器级（AllUsers）注册**，影响其他用户。若认为该行为不可接受，可在删除 HKLM 前加 `IsAdminInstallMode()` 判断，或只删除与本次 `RegistryRootForInstall()` 一致的根。
- **未做**：未实跑"先装 oWorkHelper、再取消勾选升级"的场景（原因见开头说明）；该场景需在隔离测试机（或卸载前先导出/备份既有 `oWorkhelper` 注册项）上执行。

### I-04 `FileUri` URI 转义不完整
- **位置**：`installer\iWorkHelper.iss:527-635`
- **问题**：只把空格转 `%20`，未转义 `#`、`%`、`&`、`+` 及非 ASCII；UNC 路径会生成错误的 `file://///server/share`。
- **方案**：对路径做完整百分号编码 + UNC 分支单独处理。
- **状态**：已验证
- **实现**：新增 `UriIsHexDigit`/`UriIsUnreserved`/`UriEncodeByte`/`UriEncodePath`（保留 `A-Za-z0-9-._~`、`/`、`:`，其余一律 `%XX`，非 ASCII 按 UTF-8 字节输出，支持代理对）；`FileUri` 对 `\\server\share` 形式去掉前导斜杠后输出 `file://server/share/...`，本地盘符仍为 `file:///C:/...`，并保留 `|vstolocal` 后缀。已是 `%XX` 形式的输入按原样保留，避免重复编码为 `%25XX`。`AppId`、`AppName`、`|vstolocal`、`LoadBehavior=3` 均未改动。
- **验证证据**（隔离运行，不改动仓库）：用 ISCC 编译一个临时测试脚本——按 `.iss` 中的 `BEGIN/END FILEURI HELPERS` 标记**原文抽取**该函数块，`InitializeSetup()` 对 9 条路径调用 `FileUri()` 并把结果写入 `%TEMP%`，随后返回 `False`（不执行任何安装）。结果 **9/9 PASS**，另有 2 项定点检查 PASS（对照实现：PowerShell 用 `[System.Text.Encoding]::UTF8` 逐字符百分号编码，另加手工推导的字面期望）：

  | 输入 | 输出 |
  |---|---|
  | `C:\Program Files\iWorkHelper\eWorkHelper\eWorkhelper.vsto` | `file:///C:/Program%20Files/iWorkHelper/eWorkHelper/eWorkhelper.vsto\|vstolocal` |
  | `C:\Users\张三\AppData\Local\iWorkHelper\oWorkHelper\oWorkhelper.vsto` | `file:///C:/Users/%E5%BC%A0%E4%B8%89/AppData/Local/iWorkHelper/oWorkHelper/oWorkhelper.vsto\|vstolocal` |
  | `C:\Temp\100%\oWorkhelper.vsto` | `file:///C:/Temp/100%25/oWorkhelper.vsto\|vstolocal` |
  | `C:\Temp\a%20b\o.vsto` | `file:///C:/Temp/a%20b/o.vsto\|vstolocal`（不重复编码） |
  | `C:\Temp\a%b\o.vsto` | `file:///C:/Temp/a%25b/o.vsto\|vstolocal` |
  | `C:\Temp\a#b&c+d\o.vsto` | `file:///C:/Temp/a%23b%26c%2Bd/o.vsto\|vstolocal` |
  | `C:\Temp\a?b=c;d,e@f\o.vsto` | `file:///C:/Temp/a%3Fb%3Dc%3Bd%2Ce%40f/o.vsto\|vstolocal` |
  | `\\server\share\iWorkHelper\oWorkHelper\oWorkhelper.vsto` | `file://server/share/iWorkHelper/oWorkHelper/oWorkhelper.vsto\|vstolocal` |
  | `\\srv\共享 资料\x.vsto` | `file://srv/%E5%85%B1%E4%BA%AB%20%E8%B5%84%E6%96%99/x.vsto\|vstolocal` |

  测试同时断言输出不含畸形 `file:////`、不含 `%25%20`（重复编码）、URI 中不残留原始非 ASCII 字符。
- **未做**：未验证 VSTO Loader 实际接受这些 URI 并加载加载项（需在安装后由 Office 侧确认）。

### I-05 VSTO 前置包退出码未处理 `1641`
- **位置**：`installer\iWorkHelper.iss:337`
- **问题**：只接受 `0` 与 `3010`，`1641`（`ERROR_SUCCESS_REBOOT_INITIATED`）会被判为失败。
- **方案**：`(exitCode <> 0) and (exitCode <> 3010) and (exitCode <> 1641)`。
- **状态**：已修复
- **验证证据**：`:338` 已按上述条件修改；ISCC 编译通过。
- **未做**：未真机触发 redist 返回 `1641`（需 VSTO 安装包实际请求重启）。语义上 `1641` 表示"已成功启动重启"，按成功处理；安装器本身不因此新增重启提示。

### I-06 Office 运行检测依赖窗口类名而非进程枚举
- **位置**：`installer\iWorkHelper.iss:90`（`FindWindowW` 声明）、`:366-374`（`IsProcessRunning`）、`:41-44`（`[Setup]`，指令位于 `:43-44`）
- **问题**：不可见的 Excel/Outlook 实例（自动化启动、`Visible=False`）检测不到；`FindWindow` 返回值声明为 `Longword`，而 `FindWindowW` 在 64 位下返回指针大小的 `HWND`。
- **方案**：保留窗口探测作为快速路径，同时显式启用 Inno 原生 `CloseApplications=yes` + `RestartApplications=no`；返回类型改为 `HWND`。
- **状态**：已修复
- **验证证据**：
  - `function FindWindowW(lpClassName: String; lpWindowName: String): HWND; external 'FindWindowW@user32.dll stdcall';`，`IsProcessRunning` 相应改为 `FindWindowW('XLMAIN','')` / `FindWindowW('rctrl_renwnd32','') <> 0`。`HWND` 是 Inno Pascal Script 支持的指针宽度句柄类型（Inno 自带 `Examples\CodeDll.iss` 即使用 `HWND`）；ISCC 编译通过。
  - `[Setup]` 新增 `CloseApplications=yes` 与 `RestartApplications=no`（`:43-44`），ISCC 编译接受（未识别的 `[Setup]` 指令会导致编译失败）；`CloseApplications` 使用 Windows Restart Manager 检测占用文件的进程，可覆盖不可见 Office 实例。
  - 原有手动提示（`PromptCloseProcess`）保留为第一条检查。
- **未做**：未在"Office 以不可见实例运行并占用 DLL"的真实场景下安装验证 Restart Manager 的拦截效果；`FindWindowW` 仍只覆盖有顶层窗口的实例，属设计上的快速路径而非完整枚举。

### I-07 用户可见文案包含内部里程碑代号
- **位置**：`installer\iWorkHelper.iss:484,515`
- **方案**：改为面向用户的表述，去掉内部代号。
- **状态**：已验证
- **验证证据**：两处均改为 `未检测到 .NET Framework 4.8。安装程序不会自动安装 .NET Framework 运行时，请先安装或启用后重试。`；`Select-String -Pattern 'M2 '` 在 `installer\iWorkHelper.iss` 中已无匹配（仅 `CHANGELOG.md` 与本文档在描述该修复/发现时提及 "M2"）；ISCC 编译通过。

### I-08 文档未说明静默安装必须显式传 `/COMPONENTS`
- **位置**：`installer\iWorkHelper.iss:53-54`（`[Components]` 均为 `Types: custom`，默认无勾选）+ `:506-508`（未选组件即阻断）
- **方案**：在 `docs/DEVELOPMENT.md` / `docs/RELEASE.md` 补充静默安装命令范例与 `/COMPONENTS=` 必填说明。
- **状态**：已修复
- **变更**：
  - `docs\DEVELOPMENT.md` 新增"静默安装（必须显式传 `/COMPONENTS=`）"：说明原因（两项组件均 `Types: custom`、默认不勾选，缺参时 `PrepareToInstall` 返回"请至少选择一个要安装的插件。"并记录 `PrepareToInstall blocked:`）、组件名与变体参数，并给出范例
    `iWorkHelper-Setup-1.2.0.exe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="$env:LOCALAPPDATA\iWorkHelper" /COMPONENTS=oworkhelper /OWORKHELPER_VARIANT=Local /LOG="$env:TEMP\iworkhelper-install.log"`（以及双组件与静默卸载命令）。
  - `docs\RELEASE.md` 新增"静默安装（发布验证）"章节（同样的范例 + 验证要点）。
  - `README.md` 新增"静默安装"小节。
- **未做**：未实跑 `/VERYSILENT` 且不带 `/COMPONENTS=` 的失败路径（避免在本机产生安装行为）。文档只陈述可由脚本逻辑直接推出的约束，未写入实测结论。

### I-09 诊断脚本查询的注册表路径与安装器写入路径不一致（假阴性）
- **位置**：脚本 `..\oWorkHelper\tools\OutlookResiliency\check_iworkhelper_addin_registration.ps1`；安装器 `installer\iWorkHelper.iss:655`（`RegisterAddin` 写入的 `Software\Microsoft\Office\<Host>\Addins\<AddinId>`）
- **方案**：脚本同时检查 `Office\<Host>\Addins`（无版本段）与 `Office\16.0\<Host>\Addins`，并覆盖 32/64 位视图。
- **状态**：已验证
- **变更**（仅修改该文件，未改动 `oWorkHelper` 其他内容）：
  - 主检查路径由 4 条扩展为 8 条：`HKCU`/`HKLM` × `Office\Outlook\Addins`（版本无关，安装器实际写入位置）/ `Office\16.0\Outlook\Addins` × 原生 / `Software\WOW6432Node\...`（32 位视图）。
  - 键名匹配由 `(iWorkHelper|iWorkhelper|ThisAddIn)` 改为 `(iWorkHelper|eWorkHelper|oWorkHelper|ThisAddIn)`（`Check-RegistryPath` 与 Resiliency 的 `LoadBehavior`/`DisabledItems`/`CrashingAddinList` 三处同步），确保覆盖安装器写入的 `oWorkhelper`（并兼顾 `eWorkhelper`）。
  - 结束语新增提示：安装器写入的是无版本段路径，`16.0` 路径仅供参考。
- **验证证据**（只读运行，`-OutputFile` 写到 `%TEMP%`）：
  - 修复后输出中 `[HKCU Addins (version-agnostic, written by iWorkHelper installer)]` 段命中
    `Item: oWorkhelper` / `Manifest: file:///C:/Users/Yang/Documents/github/iWorkhelper/oWorkHelper/bin/Release-Intranet/oWorkhelper.vsto|vstolocal` / `LoadBehavior: 3 (Startup Load Default)`。
  - 对照：用 `git show HEAD:tools/OutlookResiliency/check_iworkhelper_addin_registration.ps1`（只读取出修复前版本到 `%TEMP%` 运行，未做任何 checkout）在同一台机器上，旧脚本的 `[HKCU Addins]` 段显示 `Status: Found items:` 但**没有任何 `Item:`** —— 复现了"安装/注册成功后脚本仍报告未找到"的假阴性。

### I-10 `build.ps1` 中 VSTO 版本前缀与下载地址硬编码，与锁文件重复
- **位置**：`scripts\build.ps1`（原 `:152-154`）
- **方案**：从锁文件读取期望值与来源，脚本内只保留单一"锁文件可用"校验。
- **状态**：已验证
- **实现**：
  - 新增 `Get-VstoRedistExpectation($LockPath)`：读取 `prerequisites\prerequisites.lock.json`，取出 `prerequisites.vstoRuntime.source` 与 `.version` 作为唯一事实来源；保留**单一**一致性校验——`source` 必须匹配 `^https://download\.microsoft\.com/.*/vstor_redist\.exe$`，`version` 必须匹配 `^\d+\.\d+(\.\d+)*$`，锁文件或 `vstoRuntime` 节点缺失仍会失败。
  - `Test-VstoRedistPayload` 删除硬编码的 `expectedVersionPrefix`/`expectedSource`，改用锁文件派生的值；原先重复的"再读一次锁文件并比对 source"分支被移除（source 由锁文件赋值，比对已无意义）。
  - 锁文件读取提前到函数开头（快速失败），其余校验顺序与语义不变。
- **保留且未削弱的校验**：文件名必须为 `vstor_redist.exe`、PE 头合法、大小 ≥ 30MB、Authenticode 状态必须 `Valid`、签名者必须含 `Microsoft`、版本必须匹配锁文件版本前缀、SHA256 必须与锁文件一致、`sizeBytes` 必须与锁文件一致。
- **验证证据**（隔离运行，不改动仓库）：
  - `[System.Management.Automation.Language.Parser]::ParseFile` 解析 `scripts\build.ps1`：**0 语法错误**；抽取正文执行段之前的函数定义段（240 行）到临时脚本后调用。
  - 真实锁文件：通过，输出 `source=https://download.microsoft.com/download/5/d/2/5d24f8f8-efbb-4b63-aa33-3785e3104713/vstor_redist.exe`、`version=10.0.60917`（与锁文件一致，证明来自锁文件）、`sha256=CFE1A40BBE4A50022DB2164ABDB0154984E2CECB761A23CDC81CB5754F6E0A18`、`sizeBytes=41828424`、`signer=Microsoft Corporation`、`authenticode=Valid`。
  - 4 个负例全部仍被拒绝（子进程退出码 1）：source 指向非 Microsoft 域名 → `unusable source`；SHA256 篡改 → `SHA256 mismatch`；size 篡改 → `size mismatch`；version 改为 `9.9.9` → `Unexpected VSTO Runtime prerequisite version`。
- **未做**：未运行完整 `scripts\build.ps1`（原因见开头说明）。

## 低

### I-11 `ShouldExtractVstoRedist()` 定义后从未调用
- **位置**：`installer\iWorkHelper.iss`（原 `:308-311`）
- **方案**：删除。
- **状态**：已验证
- **验证证据**：删除前先用仓库范围检索确认除定义处外**无任何引用**（`installer\iWorkHelper.iss` 仅 1 处匹配，即定义本身；其余匹配只在审查报告/本文档中）；删除后 `Select-String -Pattern 'ShouldExtractVstoRedist' installer\iWorkHelper.iss` 匹配数为 **0**，ISCC 编译通过。

### I-12 回归测试覆盖缺口（x86 Office / AllUsers 安装）
- **问题**：现有 13 份日志全部为 x64 Office + CurrentUser；**AllUsers（HKLM32/HKLM64）安装与 x86 Office 路径从未验证**。
- **状态**：需真机验证
- **必须在何种机器上验证（明确要求）**：
  1. **机器 A（x86 Office）**：Windows x64 + 32 位 Office，非管理员账户 → 覆盖 `HKCU` 分支（与 I-02 同一台机器可合并执行）。
  2. **机器 B（AllUsers / HKLM）**：Windows x64 + 64 位 Office，**管理员**账户 → 覆盖 `IsAdminInstallMode=True` + `OfficeArchitecture=x64` → `HKLM64` 分支。
  3. **机器 C（AllUsers + x86 Office）**：Windows x64 + 32 位 Office，管理员账户 → `HKLM32` 分支（`IsWin64 and OfficeArchitecture=x64` 为假）。
  4. 可选 **机器 D**：32 位 Windows（`IsWin64=False`）→ `HKLM32` + `来自 32-bit Windows` 架构判定分支。
- **验证步骤（每台机器）**：
  1. 记录 `IsWin64`、`IsAdminInstallMode`、`OfficeArchitecture`、`OfficeArchitectureSource`、`OfficeVersion`（安装日志中均有）。
  2. 管理员场景使用 `/ALLUSERS`，非管理员场景使用 `/CURRENTUSER`；组件与变体显式指定：`/COMPONENTS=eworkhelper,oworkhelper /OWORKHELPER_VARIANT=Local`。
  3. 安装后核对 4 个候选注册表视图（HKCU/HKLM × 原生/`WOW6432Node`）中哪一个存在 `...\Office\<Host>\Addins\{eworkhelper,oWorkhelper}`，并用修复后的诊断脚本记录结果。
  4. 启动对应位数的 Excel 与 Outlook，确认两个加载项都能加载（Ribbon 显示，`LoadBehavior=3`）。
  5. 用 `unins000.exe /VERYSILENT` 卸载，确认注册表键与 `{app}` 目录被清理。
- **期望结果**：每种组合下加载项都注册到该位数 Office 实际读取的视图并成功加载；卸载后 `Software\Microsoft\Office\<Host>\Addins\{eworkhelper,oWorkhelper}` 与 `Software\iWorkHelper\Installer` 在对应根下不再存在。
- **判定记录要求**：逐机器记录 Office 位数、安装范围、实际注册表视图、`LoadBehavior`、Ribbon 是否显示、卸载残留情况。

## 文档

### I-13 文档漂移核查与修正
- **状态**：已验证
- **逐项结果**：
  - `docs/ARCHITECTURE.md:31-35` 关于注册与元数据的描述与实际一致（已核对），**保留未改**。
  - `docs/ARCHITECTURE.md:46-47` `AppId` 固定不变（已核对 `.iss:22`），**保留未改**；本次改动未触碰 `AppId`、`AppName`、`|vstolocal` 与 `LoadBehavior=3`。
  - `CHANGELOG.md`：`## v1.2.0` 补充日期 `2026-09-13`，并在 `Fixed` 下补充本次全部修复条目（含 I-01/I-03/I-04/I-05/I-06/I-07/I-09/I-10/I-11 与文档项）。
  - `docs/RELEASE.md`：新增"静默安装（发布验证）"章节（见 I-08），并在 `变更记录 / v1.2.0` 下补充两条说明。
  - `docs/TROUBLESHOOTING.md`：新增"诊断脚本报告未找到但安装实际成功"章节（I-09），说明旧脚本只查 `Office\16.0` 导致的假阴性及修复后的 8 条检查路径。
  - `README.md`：新增"构建前置条件"表格（Inno Setup 7 / VS2022 MSBuild + VSTO 工作负载 / .NET Framework 4.8 Developer Pack / 清单签名证书或环境变量 `IWORKHELPER_MANIFEST_CERT_THUMBPRINT` / `prerequisites\vstor_redist.exe`）与"静默安装"小节。
- **验证证据**：以上文件均已按内容复核（`read`/`git diff --stat`），未写入任何未经执行的验证结论。

---

## 变更记录

| 日期 | 内容 |
|---|---|
| 2026-09-13 | 建立跟踪文档，录入全部条目 |
| 2026-09-13 | I-01 改 `MessagesFile` 为 `compiler:Languages\ChineseSimplified.isl`、I-05 接受退出码 1641、I-07 去除"M2"文案、I-11 删除死函数 `ShouldExtractVstoRedist()`、I-06 `FindWindowW` 返回 `HWND` 并显式启用 `CloseApplications=yes`/`RestartApplications=no`、I-04 重写 `FileUri`（完整百分号编码 + UNC + 不重复编码）、I-03 新增 `CleanupUnselectedComponents()`（未选中组件的注册项与目录清理，不动共享元数据）、I-10 `build.ps1` 改以锁文件为唯一事实来源、I-09 诊断脚本补齐 8 条注册表路径并覆盖 `oWorkhelper`/`eWorkhelper` 键名、I-08/I-13 补文档（README/DEVELOPMENT/RELEASE/TROUBLESHOOTING/CHANGELOG） |
| 2026-09-13 | 验证：ISCC 7.1.0 单独编译 `.iss` 成功（退出码 0，产出 `build\iWorkHelper-Setup-1.2.0.exe`）；I-04 FileUri 隔离运行测试 9/9 + 2/2 PASS；I-10 锁文件校验隔离测试 1 正例 + 4 负例全部符合预期；I-09 修复前/后诊断输出对照确认假阴性已消除。`scripts\build.ps1` 完整构建与安装器实跑未执行（原因见"验证方式"），I-02/I-12 维持需真机验证并补充精确验证矩阵与判定标准 |
