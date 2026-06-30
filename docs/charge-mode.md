# P0 — 充电模式切换工具 (charge-mode)

```text
联想拯救者 R7000P 2020H 充电模式（养护 / 常规 / 快充）命令行切换工具
适用于 macOS 26 Tahoe + OpenCore 1.0.8 + YogaSMC 1.5.3
```

---

## 目录

1. [目标](#1-目标)
2. [调研历程与关键发现](#2-调研历程与关键发现)
3. [最终方案](#3-最终方案)
4. [安装](#4-安装)
5. [使用方法](#5-使用方法)
6. [实现细节](#6-实现细节)
7. [命令映射表](#7-命令映射表)
8. [故障排查](#8-故障排查)
9. [已知限制](#9-已知限制)
10. [未来改进](#10-未来改进)

---

## 1. 目标

通过命令行 / 脚本方式切换联想 R7000P 2020H 的充电模式：

- **养护模式 (Conservation)**：充电上限约 60%（电池寿命优先）
- **常规模式 (Normal)**：标准充电，无上限（默认）
- **快充模式 (Rapid Charge)**：100W USB-C PD 高速充电

---

## 2. 调研历程与关键发现

### 2.1 原生 DSDT 分析

通过 MaciASL 提取原生 DSDT（详见 [reference/acpi-tables/](reference/acpi-tables/)）：

| 路径 | 内容 |
|---|---|
| `\_SB.PCI0.LPC0.EC0` | EC 设备，PNP0C09 |
| `\_SB.PCI0.LPC0.EC0.VPC0` | VPC2004 设备（联想 EC 控制接口）|
| `\_SB.PCI0.LPC0.EC0.BAT0` | 电池设备，PNP0C0A |
| `\_SB.PCI0.LPC0.EC0.ADP0` | AC 适配器，ACPI0003 |

### 2.2 关键发现

#### ❌ DSDT 没有标准充电控制方法

联想 BIOS **没有实现** ACPI 标准的 `_BCM`（Battery Charge Mode）或 `_BQC`（Query Charge Mode）方法。

#### ✅ 但 DSDT 提供了 VPC2004 控制接口

`VPC0` 设备提供：

```asl
Method (VPCR, 1)  // 读 EC 寄存器 (1=VCMD, 2=VDAT)
Method (VPCW, 2)  // 写 EC 寄存器 (1=VCMD, 2=VDAT)
Method (GBMD, 0)  // 读 Battery Mode Data (返回 32-bit state)
Method (SBMC, 1)  // Set Battery Mode Control ← 关键！
```

#### ✅ SBMC 方法的命令映射

```asl
Method (SBMC, 1, NotSerialized) {
    If ((Arg0 == 3)) { BTSM = One; ... }      // 养护模式开启
    If ((Arg0 == 5)) { BTSM = Zero; ... }     // 养护模式关闭
    If ((Arg0 == 7)) { QCHO = One; BTSM=Zero; } // 快充开启
    If ((Arg0 == 8)) { QCHO = Zero; ... }     // 快充关闭
}
```

#### ❌ 但 YogaSMC 没有直接暴露 SBMC 命令

YogaSMC 1.5.3 加载了 `IdeaVPC` 类，但 **没有提供直接调 SBMC 的用户接口**。

#### ✅ IdeaVPC 监听 IORegistry 属性变化

逆向 [IdeaVPC.cpp](../reference/yogasmc-source/YogaSMC/YogaVPC/IdeaVPC.cpp) 发现：

```cpp
case kSMC_setConservation:    // message 路径
    if (*arg != conservationMode && !conservationModeLock)
        toggleConservation();  // 调 SBMC(3 或 5)
```

**通过 `setPropertiesGated` 路径**：

```cpp
} else if (key->isEqualTo(conservationPrompt)) {
    if (value->getValue() != conservationMode)
        toggleConservation();
} else if (key->isEqualTo(rapidChargePrompt)) {
    if (value->getValue() != rapidChargeMode)
        toggleRapidCharge();
}
```

#### 🔒 关键锁定机制

```cpp
bool conservationModeLock {true};   // 默认锁定！
```

**必须先解锁**才能触发 toggle：

```cpp
} else if (key->isEqualTo(batteryPrompt)) {
    conservationModeLock = value->getValue();  // 设 false 解锁
}
```

**所有"看起来生效但 EC 没真正变化"的尝试都失败于此**——ioreg 属性变了，但 `conservationModeLock=true` 阻止了实际 SBMC 调用。

### 2.3 参考资源

| 资源 | URL | 价值 |
|---|---|---|
| jimlee2048/Hackintosh-R7000P2020H | https://github.com/jimlee2048/Hackintosh-Lenovo-Legion-R7000P2020H | 同型号参考 EFI（含 SSDT-ECRW）|
| zhen-zen/YogaSMC | https://github.com/zhen-zen/YogaSMC | kext + source code |
| sangemaru/yoga-slim-7-conservation-mode | https://github.com/sangemaru/yoga-slim-7-conservation-mode | Linux 参考脚本 |

---

## 3. 最终方案

### 3.1 架构

```
----------------------------------------------------
  charge-mode CLI（Swift，编译后二进制）
    调用 IORegistryEntrySetCFProperty
----------------------------------------------------
                   ↓ 写属性
----------------------------------------------------
  YogaSMC IdeaVPC（kext，监听 setPropertiesGated）
    1. 解锁 ECLock / Battery
    2. 调 VPC0->SBMC(3/5/7/8)
----------------------------------------------------
                   ↓ ACPI 方法
----------------------------------------------------
  VPC0 (VPC2004)
    → EC0 内部写 BTSM / QCHO / CDMB 寄存器
----------------------------------------------------
                   ↓ EC 硬件
----------------------------------------------------
  联想 ITE 5570 EC 固件
    根据 BTSM/QCHO 控制充电 IC 行为
----------------------------------------------------
```

### 3.2 关键洞察

**YogaSMC 已经实现了所有逻辑**，只是没暴露用户接口。只需要：
1. 通过 IORegistry 属性触发 kext 内部 toggle
2. 按正确顺序设属性（**先解锁，再同步，再设置**）
3. 确保新值 ≠ 当前值（toggle 触发条件）

---

## 4. 安装

### 4.1 编译 charge-mode

```bash
cd features/charge-mode/src

# 编译（只需 CommandLineTools + swiftc，Swift 5.10+）
swiftc -O charge-mode.swift -o ../bin/charge-mode \
    -framework IOKit -framework Foundation

# 复制到 PATH
sudo cp ../bin/charge-mode /usr/local/bin/

# 验证
/usr/local/bin/charge-mode help
```

> 适用 macOS 15 SDK 或更新（Swift 5.10+）。macOS 14 及更早需先装 [Command Line Tools for Xcode 16+](https://developer.apple.com/download/all/)。

---

## 5. 使用方法

```bash
# 查看当前模式
sudo charge-mode status

# 切换三种模式
sudo charge-mode conservation   # 养护
sudo charge-mode normal         # 常规
sudo charge-mode rapid          # 快充

# 详细电池信息（容量/健康度，无需 sudo）
charge-mode battery

# 电量百分比
charge-mod percent

# 帮助
charge-mode help
```

### `status` 输出示例

```text
$ sudo charge-mode status

============================================================
                            充电模式
============================================================

  🛡️  养护模式 (Conservation):   ✅ 当前
  ⚡  快充模式 (Rapid Charge):     关闭
  🔌  常规充电 (Normal):           关闭

  当前激活: 🛡️ 养护模式（上限 ~60%）

============================================================
```

| 显示 | 含义 |
|---|---|
| `🛡️ 养护模式 (上限 ~60%)` | ConservationMode = true |
| `⚡ 快充模式` | RapidChargeMode = true |
| `🔌 常规充电` | 其他两个都为 false |

---

## 6. 实现细节

### 6.1 charge-mode.swift 关键代码

**完整源码**：[features/charge-mode/src/charge-mode.swift](../features/charge-mode/src/charge-mode.swift)（约 420 行）

**核心函数**：

```swift
func setMode(_ svc: io_object_t, conservation: Bool?, rapid: Bool?) {
    // 第 1 步：解锁 ECLock
    writeProperty(svc, CMD_EC_LOCK, boolToCF(false))

    // 第 2 步：解锁 conservationModeLock（关键！）
    writeProperty(svc, CMD_BATTERY_LOCK, boolToCF(false))

    // 第 3 步：从 EC 同步真实状态到 ioreg
    writeProperty(svc, CMD_UPDATE, boolToCF(true))
    usleep(500_000)

    // 第 4 步：只在需要时写入（避免 ioreg 已是目标值时 toggle 不触发）
    if current != target {
        writeProperty(svc, target_property, boolToCF(target))
    }

    // 第 5 步：再次同步确认生效
    usleep(1_000_000)
    writeProperty(svc, CMD_UPDATE, boolToCF(true))
}
```

### 6.2 IOKit 调用要点

**Swift 中 CFBoolean 处理**：

```swift
func readProperty(_ svc: io_object_t, _ name: String) -> Any? {
    let raw = IORegistryEntryCreateCFProperty(svc, name as CFString, kCFAllocatorDefault, 0)
    return raw?.takeUnretainedValue()  // 关键：必须 takeUnretainedValue
}

func cfBoolToBool(_ v: Any?) -> Bool? {
    if let b = v as? Bool { return b }
    if let n = v as? NSNumber { return n.boolValue }  // CFBoolean → NSNumber
    return nil
}
```

### 6.3 YogaSMC 属性清单

| 属性名 | 类型 | 作用 |
|---|---|---|
| `ConservationMode` | Boolean | 养护模式开关 |
| `RapidChargeMode` | Boolean | 快充模式开关 |
| `Battery` | Boolean | 解锁 conservationModeLock（设为 false）|
| `ECLock` | Boolean | 解锁 readEC/writeEC 直写 |
| `Update` | Boolean | 触发从 EC 重读状态 |

---

## 7. 命令映射表

| 用户命令 | YogaSMC 操作 | 实际 SBMC 调用 |
|---|---|---|
| `conservation` | ConservationMode = true | `SBMC(3)` → BTSM=1 |
| `normal` (从养护) | ConservationMode = false | `SBMC(5)` → BTSM=0 |
| `rapid` | ConservationMode=false, RapidChargeMode=true | `SBMC(7)` → QCHO=1, BTSM=0 |
| `normal` (从快充) | ConservationMode=false, RapidChargeMode=false | `SBMC(8)` → QCHO=0 |

### EC 寄存器含义（来自 DSDT）

| 寄存器 | Region | 偏移 | 含义 |
|---|---|---|---|
| BTSM | ERAX | 0xA7 bit 0 | Battery Threshold Status Mode（养护） |
| QCHO | ERAX | 0x8C bit 0 | Quick Charge On |
| CDMB | ERAX | 0x07 bit 0 | Charge Disable Mode Battery（备用字段） |
| ADPT | ERAX | 0xA3 bit 0 | AC Adapter Present |

---

## 8. 故障排查

### 8.1 命令无效，ioreg 属性没变化

**症状**：`charge-mode` 输出成功但 ioreg 没改

**检查**：
```bash
ioreg -l -p IOService -w 0 -c IdeaVPC | grep -E "ConservationMode|RapidChargeMode"
```

**原因**：通常是因为 `kextstat` 没看到 YogaSMC，或 IdeaVPC 没加载。

**修复**：
```bash
kextstat | grep -i YogaSMC
# 应该看到 org.zhen.YogaSMC 加载
```

### 8.2 属性变了但 EC 没切换

**症状**：ioreg 显示 ConservationMode=Yes，但 EC 实际行为没变

**原因**：`conservationModeLock=true` 没解锁

**修复**：确保 `charge-mode` 输出包含：
```
→ Battery = false（解锁 Conservation toggle）
```

### 8.3 macOS 显示"discharging"不充电（顶部状态栏不显示充电）

**症状**：pmset 显示 `discharging`，但 EC 模式已切换

**诊断**：检查 AC 适配器路径：

```bash
ioreg -l -p IOService | grep -A 30 "class AppleACPIACAdapter"
```

**根因（两大类）**：

1. **`AppleACPIACAdapter` 没认领 `ADP0` (ACPI0003)**：
   macOS `AppleACPIACAdapter` 驱动无法匹配深路径 `\_SB.PCI0.LPC0.EC0.ADP0`，
   需要 SSDT 在 `\_SB` 下重建一个 `ADP0`。

2. **100W USB-C PD 线/EC 协议不匹配**：
   `ChargingVoltage` 实际报告 8V 而不是 20V PD，
   这是 EC 与充电器之间的握手问题，**macOS 端无法修复**。
   用原厂 230W 充电器可绕过。

**已实施的方案**：[features/charge-mode/src/SSDT-ADP.dsl](../features/charge-mode/src/SSDT-ADP.dsl)

| 版本 | 行为 | 状态 |
|---|---|---|
| **v1 (221B)** | 在 `\_SB.ADP0` 代理原厂 `_PSR` 调用 | ✅ 稳定，AC 仅在唤醒后认领 |
| v2 (391B) | 直接读 EC + `Notify` | ❌ 安装后**触摸板驱动失灵**（已回退）|

**关于触摸板失灵**：v2 的 `Notify (\_SB.ADP0, 0x80)` 触发内核 panic 恢复路径，
导致 VoodooI2C / VoodooPS2Trackpad 同步崩溃。**未找到非 `Notify` 的稳定方案**。

**建议**：当前保持 v1（或不装），用 `charge-mode status` 确认模式即可。

### 8.4 "Permission denied"

每次调用都要 `sudo`，因为写 IORegistry 需要 root 权限。可选地设置 NOPASSWD：

```bash
# sudo visudo
yourusername ALL=(ALL) NOPASSWD: /usr/local/bin/charge-mode
```

---

## 9. 已知限制

| 限制 | 影响 | 绕过方法 |
|---|---|---|
| 需要 root 权限 | 每个命令都要 sudo | 设置 NOPASSWD sudo（不推荐，鉴权意义丧失）|
| macOS 顶部状态栏不显示充电 | pmset/battery UI 在 100W PD 线时显示 discharging | 换原厂 230W 充电器；或信任 `charge-mode status` 结果 |
| AC 适配器唤醒前未识别 | SSDT-ADP v1 仅在 lid 唤醒后认领 `AppleACPIACAdapter` | v2 已试但触摸板失灵 |
| 每次启动不会持久化 | 重启/睡眠激活后模式丢失（EC 默认复位） | 重启后重新执行；要持久化得写 LaunchDaemon |
| 不支持自定义阈值 | 只能 60% / 100% | 联想 EC 本身不支持自定义 |

---

## 10. 未来改进

- [ ] LaunchDaemon 实现开机自动恢复上次模式
- [ ] 包装成 `.app` 提供菜单栏 UI
- [ ] Hammerspoon 菜单栏图标
- [ ] 替代 YogaSMC，直接调 VPC0 的 SBMC 方法（绕过 kext）
- [ ] 实现 EC 寄存器直接读写（不依赖 YogaSMC 的 SSDT-ECRW）
- [ ] 内核驱动直接控制 EC（最低延迟）
- [ ] 自定义充电阈值（如果 EC 支持）
- [ ] 充电统计 / 健康度监控

---

## 附录 A：相关文件

| 文件 | 路径 |
|---|---|
| 本文档 | `docs/charge-mode.md` |
| Swift 源码 | `features/charge-mode/src/charge-mode.swift` |
| 编译后二进制 | `features/charge-mode/bin/charge-mode` |
| 安装位置 | `/usr/local/bin/charge-mode`（部署后）|
| 验证脚本 | `features/charge-mode/tests/test-charge.sh` |
| SSDT-ADP 源码 | `features/charge-mode/src/SSDT-ADP.dsl` |
| 原生 DSDT (dsl) | `reference/acpi-tables/System DSDT.dsl` |
| 原生 SSDT (dsl) | `reference/acpi-tables/System SSDT-*.dsl` |
| 诊断日志 | `logs/2026-06-29/ec-diag-*/` |
| YogaSMC 源码（参考） | `reference/yogasmc-source/YogaSMC/` |

## 附录 B：YogaSMC 源码关键文件（参考）

| 文件 | 路径 |
|---|---|
| IdeaVPC 主要实现 | `reference/yogasmc-source/YogaSMC/YogaVPC/IdeaVPC.cpp` |
| 属性名常量 | `reference/yogasmc-source/YogaSMC/message.h` |
| BMCMD 命令枚举 | `reference/yogasmc-source/YogaSMC/YogaVPC/IdeaVPC.hpp` |
| SBMC 桥接 | `reference/yogasmc-source/YogaSMC/YogaVPC.cpp` |

---

**最后更新**: 2026-06-30
**作者**: Legion R7000P 2020H Hackintosh 项目
**状态**: ✅ 验证通过，三种模式切换功能完整