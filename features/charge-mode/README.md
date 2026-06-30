# P0 — 充电模式切换（charge-mode CLI）

联想 R7000P 2020H 黑苹果下，通过命令行切换**养护 / 常规 / 快充**三种电池充电模式。

## 状态

✅ **CLI 完成并验证** —— 三种模式 ioreg 状态都能正确切换（EC 内部 BTSM / QCHO 寄存器被正确写入）

⚠️ **顶部状态栏充电图标**：原厂充电器正常显示，但 100W USB-C 充电线**仍显示"放电中"**（已知问题，非 macOS 层能修）

## 目录结构

```
features/charge-mode/
├── README.md              # 本文件
├── src/
│   ├── charge-mode.swift  # Swift 源码（编译入口）
│   └── SSDT-ADP.dsl       # AC 适配器识别（v1=稳定，v2 触发触摸板失灵，仅源码留存）
├── bin/
│   ├── charge-mode        # 编译后二进制（macOS native, ~64KB，gitignore）
│   └── SSDT-ADP.aml       # v1 编译产物（221 字节，部署用）
└── tests/
    └── test-charge.sh     # 自动化验证脚本
```

## 快速使用

```bash
# 查看当前模式
sudo /usr/local/bin/charge-mode status        # 🛡️/⚡/🔌

# 切换模式
sudo /usr/local/bin/charge-mode conservation   # 养护（上限 60%）
sudo /usr/local/bin/charge-mode normal         # 常规
sudo /usr/local/bin/charge-mode rapid          # 快充（100W PD）

# 详细电池信息（容量/健康度）
charge-mode battery

# 电量百分比
charge-mod percent

# 帮助
charge-mode help
```

## 编译

需要 Swift 5.10+（macOS 15 SDK 或 Xcode 16+），单文件编译：

```bash
cd src/
swiftc -O charge-mode.swift -o ../bin/charge-mode \
    -framework IOKit -framework Foundation
```

## 验证测试

```bash
bash tests/test-charge.sh     # 状态 → 养护 → 验证 → 常规
```

## 工作原理

```
charge-mode CLI (Swift + IOKit)
   │
   │  IORegistryEntrySetCFProperty
   ▼
YogaSMC IdeaVPC kext (监听 setPropertiesGated)
   │
   │  toggleConservation() / toggleRapidCharge()
   ▼
VPC0 (VPC2004) ACPI device
   │
   │  VPCR/VPCW 读写 EC
   ▼
EC0 (ITE 5570) - 写 BTSM / QCHO 寄存器
```

### 关键锁定机制（最大坑）

`IdeaVPC` 内部有 `conservationModeLock {true}`，**必须**先把它解了，否则属性变化了但 EC 没切。

解锁方法（已自动化）：

```swift
writeProperty(svc, "Battery", kCFBooleanFalse)   // 解 conservationModeLock
writeProperty(svc, "ECLock",  kCFBooleanFalse)   // 解 readEC/writeEC
writeProperty(svc, "Update",  kCFBooleanTrue)    // 从 EC 同步真实状态
```

### 命令映射

| CLI  | YogaSMC 属性 | EC 内 SBMC 调用 | 寄存器影响 |
|---|---|---|---|
| `conservation` | ConservationMode = true | SBMC(3) | BTSM = 1 |
| `normal` | ConservationMode = false | SBMC(5) | BTSM = 0 |
| `rapid` | ConservationMode=false, RapidChargeMode=true | SBMC(7) | QCHO=1, BTSM=0 |
| `normal`（从快充）| ConservationMode=false, RapidChargeMode=false | SBMC(8) | QCHO=0 |

## 详细文档

完整调研过程和实现细节：[../../docs/charge-mode.md](../../docs/charge-mode.md)

## 已知限制

| 限制 | 影响 | 绕过 |
|---|---|---|
| 需要 root 权限 | 每次命令都要 `sudo` | 无（IORegistry 写入需要） |
| 100W USB-C 线 pmset 仍显示 discharging | macOS UI 看不到，但 EC 实际按模式切 | 用 `status` 命令确认；或换原厂 230W 充电器 |
| 不支持自定义阈值 | 联想 EC 本身只支持 60% / 100% 两档 | 不可绕过 |
| 重启后丢失 | EC 默认复位到常规 | 要 LaunchDaemon，或写 `EC 0x07` 永久值 |

## 试过但没成的方案

- **直接调 `_SB.PCI0.LPC0.EC0.VPC0._SBV/SBMC` ACPI 方法**：macOS 不允许应用层调任意 ACPI 方法
- **SSDT-ADP v2（直接读 EC + `Notify`）**：v2 触发触摸板驱动崩溃，源码保留为参考
- **SSDT-BAT（覆盖 _BST 加 Notify）**：v1 重复定义 `OBST/OBAC/PBST` 与原生 DSDT 冲突，已弃用

## 未来改进

- [ ] 菜单栏图标（UI 模式调用 CLI）
- [ ] LaunchDaemon 实现持久化模式（开机恢复）
- [ ] Hammerspoon 集成
- [ ] 修复 AC 适配器 UI 识别（v2 触摸板失灵问题排查）
