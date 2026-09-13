# iWorkHelper Installer Release

## 当前版本

当前安装器产品版本：`1.2.0`。

安装器文件版本等必须为四段数值格式时使用 `1.2.0.0`。默认输出：

```text
build/iWorkHelper-Setup-1.2.0.exe
```

## 版本来源

| 项目 | 来源 |
| --- | --- |
| InstallerVersion | `scripts/build.ps1` 参数，默认 `1.2.0` |
| InstallerFileVersion | 由产品版本派生，默认 `1.2.0.0` |
| eWorkHelperVersion | eWorkHelper `AssemblyInformationalVersion` |
| oWorkHelperVersion | oWorkHelper `AssemblyInformationalVersion` |

## 打包输入

| 组件 | 配置 | 来源 |
| --- | --- | --- |
| eWorkHelper | `Release|Any CPU` | `../eWorkHelper/bin/Release` |
| oWorkHelper Local | `Release-Intranet|Any CPU` | `../oWorkHelper/bin/Release-Intranet` |
| oWorkHelper Baidu | `Release-Internet|Any CPU` | `../oWorkHelper/bin/Release-Internet` |

## 发布前检查

- 插件 Release 构建均为 0 Error / 0 Warning。
- `OfflineTester --selftest` 通过。
- `scripts/build.ps1` 完整构建通过。
- `staging` 通过 `.vsto`、`.dll.manifest`、主 DLL 和依赖完整性校验。
- Local 与 Baidu Variant 主 DLL hash 不应相同。
- `packaged-components.json` 不包含私钥、密码或本机绝对路径。
- `.gitignore` 覆盖生成目录、前置依赖 payload、日志、缓存、证书和本地配置。

## 变更记录

### v1.2.0

- 统一安装器版本为 `1.2.0`，文件版本使用 `1.2.0.0`。
- 默认输出 `iWorkHelper-Setup-1.2.0.exe`。
- 保留 eWorkHelper 与 oWorkHelper 双组件安装，oWorkHelper 默认 Variant 为 Baidu。
- VSTO Runtime 前置依赖支持本地校验和安装/修复。
- 精简 docs，合并阶段验证和诊断记录为长期维护文档。
