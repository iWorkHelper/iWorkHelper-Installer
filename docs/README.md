# iWorkHelper 安装器文档

本目录是统一 MSI + EXE 安装器的维护入口：

- [Requirements.md](Requirements.md)：范围、需求与验收矩阵。
- [Architecture.md](Architecture.md)：WiX、Bundle、MSI、双作用域和 Feature 设计。
- [Build.md](Build.md)：统一构建、Payload 和发布前检查。
- [Registration.md](Registration.md)：Excel / Outlook VSTO 注册方式。
- [Testing.md](Testing.md)：静态、构建及真实安装生命周期测试。
- [KnownIssues.md](KnownIssues.md)：已知限制、踩坑和阻塞项。

文档与安装器源码必须同步修改。构建成功仅代表安装器能生成，不代表 Office 加载、修改、修复、卸载和升级已经验证。

