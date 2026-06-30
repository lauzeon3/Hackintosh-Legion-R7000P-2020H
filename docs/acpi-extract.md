# 如何提取自己的 ACPI 表

> **本项目的 SSDT 调试、EC 寄存器分析都基于你**自己机器**的 ACPI 表**。
> 不要直接复用作者提取的表格 —— 即使同一型号，BIOS 版本不同表也可能不一样。

---

## 路径一：macOS 下用 OCAT + MaciASL（推荐作者路线）

### 工具

| 工具 | 来源 |
|---|---|
| **OCAT**（OpenCore Auxiliary Tools） | https://github.com/ic005k/OCAuxiliaryTools/releases |
| **MaciASL**（ACPI 编译器 GUI） | https://github.com/acidanthera/MaciASL/releases |

### 步骤

1. 打开 **OCAT**，菜单 `工具 → 导出 ACPI`
   - 会一次性导出 DSDT、所有 SSDT 的 `.aml` 二进制文件
   - 默认输出到 `~/Desktop/ACPI/` 或自选目录
2. 打开 **MaciASL**，文件 -> 从 ACPI 中获取 -> 选择 DSDT
   - 弹出的界面，按快捷键 ⌘S 保存到自选目录，建议选择 `.dsl` 格式
3. 把 `.dsl` 集合放到 `reference/acpi-tables/`
4. MaciASL 里直接搜关键字定位目标方法：

| 想做的事 | 搜什么 |
|---|---|
| 充电模式 EC 命令 | `_SB.PCI0.LPC0.EC0.VPC0` / `SBMC` |
| USB 端口映射 | `_SB.PCI0.XHC` 或 `EHC1` |
| 触摸板 I2C HID | `I2C` / `HID` |
| 屏幕亮度 | `BRT` / `_BCL` / `_BCM` |
| 电源按钮 / 休眠 | `_PWR` / `SLP` |

> ⚠️ macOS 下提取的 ACPI 表**已经过 AppleACPIPlatform patch**，如果你要研究 EC 寄存器**原始行为**，还是建议用下面的 Linux 路径。

---

## 路径二：Linux Live USB 下提取（最贴近硬件原貌）

> 适合需要分析 EC 原始寄存器、S3 唤醒路径的深度调试。

### 工具

```bash
# Ubuntu/Debian Live USB
sudo apt install acpica-tools
```

### 步骤

1. 启动到 **Ubuntu / Fedora Live USB**
2. 终端执行：

```bash
mkdir -p ~/acpi-tables && cd ~/acpi-tables
sudo acpidump -b          # 一次性导出所有 .aml

# 反编译为可读源码
iasl -da DSDT.aml SSDT*.aml
```

3. 现在 `~/acpi-tables/` 下会有几十个 `.dsl` 文件

---

## 写补丁 / SSDT

参考本项目 `features/charge-mode/src/SSDT-ADP.dsl` 学会如何：
- 用 `External` 引用原生方法
- 用 `If (...) { ... } Else { ... }` 代理原生返回值
- 用 `Notify` 触发状态变化

编译：

```bash
iasl SSDT-MyPatch.dsl          # → SSDT-MyPatch.aml
cp SSDT-MyPatch.aml /Volumes/EFI/EFI/OC/ACPI/
# 在 config.plist 加载，重启
```

---

## ⚠️ 不要做的事

- ❌ **不要直接复用作者 dump 的 DSDT/SSDT** —— 同型号不同 BIOS 版本表会变
- ❌ **不要把 dump 出来的表格提交到 Git 仓库** —— 包含你机器的 `\_SB` 路径，可被关联识别
- ❌ **不要在 Windows 下用 AIDA64 提取的 ACPI 表** —— 它会把 EC 操作屏蔽掉

---

## 工具速查

| 命令 / 工具 | 用途 |
|---|---|
| OCAT 导出 ACPI | macOS 下批量 dump 表 |
| MaciASL `⌘D` | GUI 反编译 / 编译 |
| `iasl -d` | 命令行反编译 `.aml` → `.dsl` |
| `iasl` | 命令行编译 `.dsl` → `.aml` |
| `acpidump -b` | Linux 下批量 dump |

---

## 参考

- [ACPI 规范 6.5](https://uefi.org/specifications)
- [OpenCore ACPI 文档](https://dortania.github.io/OpenCore-Install-Guide/acpi/)
- [OCAT 使用指南](https://github.com/ic005k/OCAuxiliaryTools/wiki)
- [acpica-tools 项目](https://www.intel.com/content/www/us/en/developer/articles/tool/intel-acpi-component-architecture-download.html)