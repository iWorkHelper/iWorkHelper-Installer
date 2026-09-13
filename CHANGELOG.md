# Changelog

## v1.2.0

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

### Known Issues

- 当前安装器注册元数据仍标记为 `Development/Test` 信任策略；企业级生产发布前应替换为正式代码签名/清单签名策略。
- AllUsers 以及完整 Windows/Office x86/x64 组合仍需在目标环境矩阵中继续验证。
