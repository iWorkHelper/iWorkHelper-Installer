# VSTO 注册

## 注册键

Excel：

```text
HKCU/HKLM\Software\Microsoft\Office\Excel\Addins\eWorkhelper
```

Outlook：

```text
HKCU/HKLM\Software\Microsoft\Office\Outlook\Addins\oWorkhelper
```

每个键写入 `FriendlyName`、`Description`、DWORD `LoadBehavior=3` 和 `Manifest`。`Manifest` 使用：

```text
file:///<installed deployment manifest>.vsto|vstolocal
```

`vstolocal` 强制从 MSI 安装目录加载，不写 ClickOnce cache。per-user / per-machine 由 `HKMU` 自动映射到 HKCU/HKLM。组件属于对应 Feature，因此移除 Excel Feature 不会删除 Outlook 注册，反之亦然。

## 64 位约束

组件和注册表搜索均使用 64 位视图，只注册 Office x64 路径。没有 WOW6432Node 注册，也不支持 32 位 Office。

## 清单要求

Release Build 生成的 `.vsto` 引用同目录 `.dll.manifest`，后者列出主程序集与依赖。安装器必须保持文件名和相对关系，且正式清单签名链在目标机可被信任。安装器 Authenticode 签名不能替代 VSTO manifest 签名。

