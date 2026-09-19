# Changelog

## Unreleased

### Added

- 启动时检查固定 AppId 的 Inno 卸载记录与安装器元数据，支持首次安装、原路径升级、同版本修复和高版本降级阻止。
- 继承有效安装路径、安装范围和 oWorkHelper OCR Variant；不一致或失效安装记录默认阻止自动覆盖。
- 升级前保存关键注册信息，安装失败时恢复元数据与 VSTO Manifest 注册，并补充版本/状态策略测试脚本。

## v1.3.0 - 2026-09-20

### Changed

- 更新统一安装器、eWorkHelper 和 oWorkHelper 的产品版本至 `1.3.0`。
- 安装包文件版本更新为 `1.3.0.0`。
- 纳入安装状态继承、升级回滚和版本策略改进。

## v1.2.1 - 2026-09-19

### Changed

- 更新统一安装器、eWorkHelper 和 oWorkHelper 的产品版本至 `1.2.1`。
- 安装包文件版本更新为 `1.2.1.0`。

## v1.2.0 - 2026-09-13

### Added

- 新增统一安装器，使用 Inno Setup 7 生成单一 Windows 安装向导。
- 支持选择安装 Excel 插件 `eWorkHelper`、Outlook 插件 `oWorkHelper` 或同时安装两者。
- 支持 `CurrentUser` 与 `AllUsers` 安装范围、自定义安装目录、Office Host 检测和 Office x86/x64 架构检测。
- 支持自动检测、安装或修复 VSTO Runtime prerequisite。
- 打包 `oWorkHelper` 的 `Local` 与 `Baidu` 两种运行模式，安装时默认选择 `Baidu`。

### Improved

- 安装器构建流程会重新构建插件、收集发布文件、校验 staging 内容，并避免打包 `bin/Debug`、`obj` 或调试文件。
- VSTO 清单签名配置改为由受保护证书存储、环境变量或 MSBuild 参数提供，源码不保存 PFX、私钥或固定证书指纹。
- README 与 `/docs` 已整理为面向 GitHub 发布的长期维护文档。

### Fixed

- 修复 VSTO Runtime 检测逻辑，兼容 `v4R` 与 Office 自带 `v4` 注册项。
- 修复安装器文件版本格式，Inno Setup `VersionInfoVersion` 与 `VersionInfoProductVersion` 使用合法四段版本 `1.2.0.0`。
- 修复安装向导界面语言：`MessagesFile` 由英文 `compiler:Default.isl` 改为 `compiler:Languages\ChineseSimplified.isl`，向导内置页面与安装器自定义消息现在统一为简体中文。
- 修复 VSTO Runtime 前置包退出码判定：`1641`（`ERROR_SUCCESS_REBOOT_INITIATED`，已启动重启）不再被误判为安装失败。
- 修复 VSTO Manifest URI 转义：安装路径中的非 ASCII 字符（如中文用户名）、`%`、`#`、`&`、`+` 等现在按 UTF-8 百分比编码，UNC 路径生成 `file://server/share/...` 而非畸形的 `file://///server/share/...`；已是 `%XX` 形式的转义不会被重复编码。
- 修复升级时取消勾选组件不清理的问题：`ssPostInstall` 阶段会删除未选中组件的 Office 注册项与 `{app}` 下对应子目录，被取消勾选的插件不再被 Office 加载；共享元数据子键不受影响。
- 修复 Office 运行检测：`FindWindowW` 返回值类型由 `Longword` 改为指针宽度 `HWND`，并显式启用 `CloseApplications=yes` / `RestartApplications=no`，由 Restart Manager 兜底检测不可见的 Office 实例。
- 修复诊断脚本 `check_iworkhelper_addin_registration.ps1` 的假阴性：同时检查版本无关路径 `Software\Microsoft\Office\<Host>\Addins` 与 `Office\16.0\<Host>\Addins`，覆盖 HKCU/HKLM 与原生/`WOW6432Node` 视图，并识别 `oWorkhelper` / `eWorkhelper` 键名。
- 清理用户可见文案中的内部里程碑代号（"M2 安装器"）。
- 删除 `.iss` 中定义后从未调用的 `ShouldExtractVstoRedist()`。
- 移除 `scripts/build.ps1` 中重复硬编码的 VSTO Runtime 版本前缀与下载地址，改为以 `prerequisites/prerequisites.lock.json` 为唯一事实来源（文件名、PE 头、大小下限、Authenticode 签名、Microsoft 发布者、版本、SHA256、大小校验全部保留）。
- 文档补充静默安装必须显式传 `/COMPONENTS=` 的约束与命令范例（`README.md`、`docs/DEVELOPMENT.md`、`docs/RELEASE.md`）。
- `README.md` 补充构建前置条件（清单签名证书或 `IWORKHELPER_MANIFEST_CERT_THUMBPRINT`、`prerequisites\vstor_redist.exe`、Inno Setup 7）。

### Known Issues

- 当前安装器注册元数据仍标记为 `Development/Test` 信任策略；企业级生产发布前应替换为正式代码签名/清单签名策略。
- AllUsers 以及完整 Windows/Office x86/x64 组合仍需在目标环境矩阵中继续验证。
