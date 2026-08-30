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

`vstolocal` 强制从 MSI 安装目录加载，不写 ClickOnce cache。per-user / per-machine 由 `HKMU` 自动映射到 HKCU/HKLM。Outlook Local 和 LocalOnline 各自的注册组件都写入上面同一个 Add-in 键，但 MSI 互斥条件确保任一时刻只安装一个；其 Manifest 分别指向 `Outlook\Local` 或 `Outlook\LocalOnline`。因此 Outlook 中只显示一个 `oWorkHelper`，切换版本会替换 Manifest 和 edition 标记，而不会创建第二个 Add-in 身份。

## 64 位约束

组件和注册表搜索均使用 64 位视图，只注册 Office x64 路径。没有 WOW6432Node 注册，也不支持 32 位 Office。

## 清单要求

Release Build 生成的 `.vsto` 引用同目录 `.dll.manifest`，后者列出主程序集与依赖。安装器必须保持文件名和相对关系，且正式清单签名链在目标机可被信任。安装器 Authenticode 签名不能替代 VSTO manifest 签名。
