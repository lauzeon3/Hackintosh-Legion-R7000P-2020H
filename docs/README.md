# docs — 项目文档

按功能组织的文档。每篇独立可读。

## 索引

| 文档 | 内容 |
|---|---|
| [charge-mode.md](charge-mode.md) | P0 — 电池充电模式切换（养护/常规/快充） |
| [acpi-extract.md](acpi-extract.md) | 如何提取自己机器的 ACPI 表（macOS OCAT + MaciASL 路线） |

---

## 引用约定

文档里引用 ACPI 表某行写法（方便从仓库根目录跳转）：

```
ACPI: System DSDT.dsl:4476 (EC0 设备)
```

文件路径以"反编译后放在 reference/acpi-tables/ 下"为前提 —— 该目录**不入仓**，见根 [README](../README.md) 的说明。