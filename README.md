# Legion R7000P 2020H Hackintosh

本仓库记录联想拯救者 R7000P 2020H (82GR)在 Hackintosh 上的**具体问题排查和工具实现**。

- 平台 macOS 26.0 Tahoe + OpenCore 1.0.8 + AMD Ryzen 7 4800H
- 这里不再维护通用 EFI，只放「特定机型的补充工具和配置」
- 完整的 EFI、SSDT 母板需要自行配置：OpenCore 起手套件（[dortania's OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/)）

---

> ## ⚠️ 免责声明
>
> 本项目仅适用于**联想拯救者 R7000P 2020H**，在 macOS 26 Tahoe + OpenCore 1.0.8 + YogaSMC 1.5.3 上自测通过。**其他型号 / 系统版本未经测试，套用风险自担**。
>
> **已知高风险操作**：
>
> - ACPI 表重写（SSDT 注入） → 错误实现可能让设备无法启动
> - EC 寄存器写入（`SBMC` 命令） → 错误值可能破坏电池保护
> - BIOS 设置修改 / 刷新 → 失败可能"变砖"
> - 第三方 kext 注入（itlwm、YogaSMC、NootedRed 等）→ 可能与系统更新冲突
>
> **本项目按"现状"提供，本人不承担因使用本项目造成的任何责任**，包括但不限于：
>
> - 设备硬件损坏
> - 数据丢失
> - 失去厂商保修
> - 与联想用户协议 / 当地法规冲突
>
> 不熟悉 ACPI / OpenCore 工作原理前，请先阅读 [OpenCore 官方文档](https://dortania.github.io/OpenCore-Install-Guide/)。
> **动手之前，请确保已备份 EFI 分区、原生 DSDT、关键数据。并结合自己机器的 ACPI Tables 分析。**

---

## 🚀 已完成功能

### [CLI 切换充电模式](docs/charge-mode.md) ✅

使用 100W PD C转方口充电线 + 酷态科10号Mini 120W 快充氮化镓，代替 230W 原装电源适配器，实现 `轻量办公` 的充电需求。通过命令行实现在 macOS 系统，切换 **养护 / 常规 / 快充** 电池充电模式。

```bash
sudo charge-mode status        # 🛡️ 养护模式 / ⚡ 快充模式 / 🔌 常规充电
sudo charge-mode conservation  # 切到养护（上限 ~60%）
sudo charge-mode normal        # 切到常规
sudo charge-mode rapid         # 切到快充
sudo charge-mode battery       # 详细电池信息
```

**实现原理**：通过 IORegistry 写 `IdeaVPC` 节点的 `ConservationMode` / `RapidChargeMode` 属性，YogaSMC kext 监听属性变化并调 `SBMC(3/5/7/8)` 命令控制 EC 内部寄存器。

**使用说明**：使用 100W USB-C 充电线时，需要先切换到 `养护模式` 再切回 `常规模式` 或 `快充模式` 来激活充电。由于电池充电图标不显示，可通过 `charge-mode battery` 查看当前电池容量来确认是否在充电，使用原厂电源适配器充电图标显示正常。

**测试结果**：

| 模式 | ioreg `ConservationMode` | ioreg `RapidChargeMode` | 行为 |
|---|---|---|---|
| 养护 | `Yes` | `No` | EC 限制充至 ~60% |
| 常规 | `No` | `No` | 100% 充满 |
| 快充 | `No` | `Yes` | 100W PD 高速 |

> ⚠️ **macOS 顶部状态栏问题**：使用 100W USB-C 线时 macOS 无法激活充电标志，Windows 系统同理。原因见 [已知问题](#-已知问题)。

详细文档：[docs/charge-mode.md](docs/charge-mode.md) · 源码：[features/charge-mode/](features/charge-mode/)

---

## 📋 路线图

| 优先级 | 功能 | 状态 | 计划方案 |
|---|---|---|---|
| P0 | 切换养护/常规/快充 | ✅ 完成 | 见 [docs/charge-mode.md](docs/charge-mode.md) |
| P1 | 内置 Wi-Fi 修复 | ⬜ 待办 | 解决 `IOSkywalkFamily` 冲突  `AirportItlwm` 问题 |
| P2 | 睡眠/唤醒排查 | ⬜ 待办 | `pmset` 基线 + 自定义 `sleep-diag.sh` |
| P3 | 触摸板失灵 | ⬜ 待办 | 收集失灵现场 IOReg 日志后定位 |

---

## 🔧 已知问题

| 问题 | 现象 | 状态 |
|---|---|---|
| 100W USB-C 线不显示充电 | 激活充电时 pmset 永远 "discharging"，但实际在充电 | macOS 端无法修复，属 EC/PD 协议层差异 |
| SSDT-ADP v2 触发触摸板失灵 | v2 写 EC 寄存器的 `Notify` 触发内核恢复路径 | 回退到 v1（直接代理原厂 `_PSR`）已恢复 |

---

## 💻 硬件概览

| 组件 | 型号 | macOS 状态 |
|---|---|---|
| CPU | AMD Ryzen 7 4800H (8C/16T) | ✅ |
| 核显 | Radeon RX Vega (Renoir) | ✅ |
| 独显 | NVIDIA RTX 2060 | 🚫 屏蔽（macOS 无解） |
| 内存 | 16GB DDR4-3200 | ✅ |
| 无线网卡 | Intel AX200 | ✅ |
| 有线网卡 | Realtek RTL8111 | ✅ |
| 声卡 | Realtek ALC257 | ✅ layout-id 101 |
| 触摸板 | I2C HID + PS2 | 🟡 偶发失灵 |
| 电池 | LCFC BAT20101001 (80Wh) | ✅ |
| 屏幕 | BOE 1080p 144Hz | ✅ |

---

## 📁 项目结构

```
Hackintosh-Legion-R7000P-2020H/
├── README.md                 # 本文件（GitHub 主页）
├── docs/                     # 详细文档（按功能命名：charge-mode.md / wifi-fix.md / ...）
├── features/                 # 每个功能一个目录，按功能名分
│   ├── charge-mode/          # 充电模式 CLI（养护 / 常规 / 快充）
│   │   ├── src/              # Swift 源码 + SSDT 源（.dsl）
│   │   ├── bin/              # SSDT .aml（部署）+ 编译产物
│   │   ├── tests/            # 验证脚本
│   │   └── README.md
│   └── <新功能>/              # 未来：wifi-fix、sleep、trackpad ...
├── reference/                # 第三方代码库、ACPI 表文件
├── scripts/                  # 通用诊断脚本（ec-diag 等）
└── .gitignore
```

---

## 🛠 开发者备忘

💡 完整 ACPI 表反编译存放路径：`reference/acpi-tables/`，该目录**不入仓**（不同 BIOS 表不同，复用会误导）。请按 [docs/acpi-extract.md](docs/acpi-extract.md) 提取自己机器的表。

要为本机添加新功能：

1. 在 `features/<feature-name>/` 建目录（例：`features/wifi-fix/`）
2. `src/` 放源码，`bin/` 放 SSDT .aml（部署文件；编译产物会进 .gitignore）
3. 在 `docs/` 写一份 `<feature>.md`（调研过程、原理、用法）
4. 更新本 README 的 🚀 已完成功能 + 📋 路线图
5. 提交后开 PR

---

## 🙏 致谢

- [OpenCore](https://github.com/acidanthera/OpenCorePkg) — 引导加载
- [YogaSMC](https://github.com/zhen-zen/YogaSMC) — VPC2004 兼容层
- [dortania](https://dortania.github.io/) — Hackintosh 配置指南
- [OpenIntelWireless](https://github.com/OpenIntelWireless) — itlwm / HeliPort
