# Changelog

本文件记录 iWorkHelper Installer 的公开版本变更。

## [1.0.9] - 2026-08-30

### Added

- 为 Outlook 增加互斥的 Local 与 Local + Online 安装选项，并分别收集和验证两个 Release Payload。
- 增加中英文 Outlook edition 选择界面、命令行变量和自动化回归检查。

### Changed

- 首次安装默认选择 Excel、Outlook 与 Local + Online；维护和升级保留已安装的 Outlook edition。
- 扩展 MSI、Bundle、Payload 和数据库验证，覆盖 Feature 互斥、版本一致性与升级状态恢复。
- 更新安装、生命周期、注册、构建和测试文档以反映当前实现。

### Fixed

- 修复 Major Upgrade 时无法从 related MSI 恢复 Feature 状态的问题。
- 修复启用 Feature selection 后全新安装默认状态及无界面执行返回码处理。
