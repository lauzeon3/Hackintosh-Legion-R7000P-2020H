// charge-mode.swift
// 控制联想 R7000P 2020H 充电模式（养护/常规/快充）
// 通过 IORegistryEntrySetCFProperty 写 IdeaVPC 属性触发切换

import Foundation
import IOKit
import Darwin  // mach_port_self, mach_port_deallocate

// MARK: - IOKit 帮助

func findIdeaVPC() -> io_object_t? {
    var port: mach_port_t = 0
    let kr = IOMainPort(0, &port)
    guard kr == KERN_SUCCESS else {
        FileHandle.standardError.write("IOMainPort failed: \(kr)\n".data(using: .utf8)!)
        return nil
    }

    let matching = IOServiceMatching("IdeaVPC") as NSMutableDictionary
    var iter: io_iterator_t = 0
    let kr2 = IOServiceGetMatchingServices(port, matching, &iter)
    guard kr2 == KERN_SUCCESS else {
        FileHandle.standardError.write("GetMatchingServices failed: \(kr2)\n".data(using: .utf8)!)
        return nil
    }
    defer { IOObjectRelease(iter) }

    let svc = IOIteratorNext(iter)
    return svc == 0 ? nil : svc
}

func readProperty(_ svc: io_object_t, _ name: String) -> Any? {
    let cfName = name as CFString
    guard let raw = IORegistryEntryCreateCFProperty(svc, cfName, kCFAllocatorDefault, 0) else {
        return nil
    }
    return raw.takeUnretainedValue()
}

func writeProperty(_ svc: io_object_t, _ name: String, _ value: Any) -> Bool {
    let cfName = name as CFString
    let cfVal = value as Any as CFTypeRef
    let r = IORegistryEntrySetCFProperty(svc, cfName, cfVal)
    return r == KERN_SUCCESS
}

func boolToCF(_ b: Bool) -> CFBoolean {
    return b ? kCFBooleanTrue : kCFBooleanFalse
}

func cfBoolToBool(_ v: Any?) -> Bool? {
    guard let cf = v else { return nil }
    if let b = cf as? Bool { return b }
    if let n = cf as? NSNumber {
        let unmanaged = Unmanaged<CFBoolean>.fromOpaque(Unmanaged.passUnretained(n).toOpaque()).takeUnretainedValue()
        if CFGetTypeID(unmanaged) == CFBooleanGetTypeID() {
            return CFBooleanGetValue(unmanaged)
        }
    }
    return nil
}

// MARK: - 模式定义

let CMD_CONSERVATION = "ConservationMode"
let CMD_RAPID = "RapidChargeMode"
let CMD_EC_LOCK = "ECLock"
let CMD_UPDATE = "Update"
let CMD_BATTERY_LOCK = "Battery"   // 解锁 conservationModeLock

/// 强制从 EC 同步状态到 ioreg
func syncFromEC(_ svc: io_object_t) {
    _ = writeProperty(svc, CMD_UPDATE, boolToCF(true))
}

func printStatus(_ svc: io_object_t) {
    let W = 60
    let line = String(repeating: "=", count: W)
    let title = "充电模式"
    let pad = max(0, (W - title.count) / 2)

    let cons = cfBoolToBool(readProperty(svc, CMD_CONSERVATION)) ?? false
    let rapid = cfBoolToBool(readProperty(svc, CMD_RAPID)) ?? false

    print("")
    print(line)
    print(String(repeating: " ", count: pad) + title)
    print(line)
    print("")

    // 三模式状态（统一格式：emoji + 名称 + 状态）
    print("  🛡️  养护模式 (Conservation):   \(cons  ? "✅ 当前" : "  关闭")")
    print("  ⚡  快充模式 (Rapid Charge):   \(rapid ? "✅ 当前" : "  关闭")")
    print("  🔌  常规充电 (Normal):         \((!cons && !rapid) ? "✅ 当前" : "  关闭")")

    // 当前激活模式（详细描述）
    let active: (emoji: String, label: String)
    if cons {
        active = ("🛡️", "养护模式（上限 ~60%）")
    } else if rapid {
        active = ("⚡", "快充模式")
    } else {
        active = ("🔌", "常规充电")
    }
    print("")
    print("  当前激活: \(active.emoji) \(active.label)")

    print("")
    print(line)
    print("")
}

// MARK: - 电池专用命令（battery）

func printBatterySection() {
    guard let info = readBatteryInfo() else {
        print("  ✗ 无法读取 AppleSmartBattery 属性")
        print("    可能原因: AppleSmartBatteryManager.kext 未加载")
        return
    }

    let voltageV = Double(info.voltageMV) / 1000.0
    let curWh = Double(info.currentMah) * voltageV / 1000.0
    let fullWh = Double(info.fullMah) * voltageV / 1000.0
    let designWhStd = Double(info.designMah) * 15.4 / 1000.0
    let healthPct = Double(info.fullMah) / Double(info.designMah) * 100.0

    // 健康度条
    let healthBarLen = 24
    let filledLen = Int((healthPct / 100.0) * Double(healthBarLen))
    let bar = String(repeating: "█", count: filledLen)
         + String(repeating: "░", count: healthBarLen - filledLen)

    let mAhFmt = { (n: Int) in String(format: "%5d mAh", n) }
    let whFmt  = { (w: Double) in String(format: "%6.2f Wh", w) }
    let pctFmt = { (p: Double) in String(format: "%5.1f%%", p) }

    print("  当前容量:    \(mAhFmt(info.currentMah))   (\(whFmt(curWh)) @ \(String(format: "%.2fV", voltageV)) 实时)")
    print("  满电容量:    \(mAhFmt(info.fullMah))   (\(whFmt(fullWh)) @ \(String(format: "%.2fV", voltageV)) 实时)")
    print("  设计容量:    \(mAhFmt(info.designMah))   (\(whFmt(designWhStd)) @ 15.4V 标准锂电)")
    print("")
    print("  电池健康度:  \(pctFmt(healthPct))   (= 满电 / 设计)")
    print("               [\(bar)]")
    print("")
    print("  循环次数:    \(info.cycleCount) 次")
    print("  当前电压:    \(String(format: "%.2f V", voltageV))   (实时，会随充电变化)")

    if let fc = info.fullyCharged {
        print("  EC 充满标志:  \(fc ? "✅ Yes" : "❌ No")   (ChargingState 寄存器)")
    }

    // ===== 状态字解析（_BST[0]）=====
    if let bs = info.batteryState {
        let chargingStr = (info.charging ?? false) ? "✅ 充电中" : "❌ 未充"
        let dischargingStr = (info.discharging ?? false) ? "✅ 放电中" : ""
        let criticalStr = (info.critical ?? false) ? "⚠️ 低电量" : ""
        let acStr = (info.externalConnected ?? false) ? "✅ AC 在位" : "❌ AC 不在位"

        print("")
        print("  电池状态字:    0x\(String(bs, radix: 16, uppercase: true))  (来自 _BST[0])")
        print("    ├─ 充电状态:  \(chargingStr)")
        print("    ├─ 放电状态:  \(dischargingStr)")
        print("    ├─ 低电量:    \(criticalStr)")
        print("    └─ AC 适配器:  \(acStr)")
    }

    // ===== 充电器数据 =====
    if let cv = info.chargingVoltage, let cc = info.chargingCurrent {
        let voltageV = Double(cv) / 1000.0
        let currentA = Double(cc) / 1000.0
        let wattW = voltageV * currentA
        print("")
        print("  充电器数据:    \(String(format: "%.1f V", voltageV)) × \(String(format: "%.2f A", currentA)) = \(String(format: "%.1f W", wattW))")
        if cc < 100 {
            print("  ⚠️  充电电流接近 0（< 100 mA），可能 EC/PD 协议不匹配")
        }
    }
    if let ia = info.instantAmperage {
        let a = Double(ia) / 1000.0
        let dir = a >= 0 ? "充电" : "放电"
        print("  实时电流:      \(String(format: "%.2f A", abs(a))) (\(dir))")
    }
}

func printPercentCompareSection() {
    guard let info = readBatteryInfo() else {
        print("  ✗ 无法读取电池信息")
        return
    }

    let calcPercent = Double(info.currentMah) / Double(info.fullMah) * 100.0
    let pmset = readPmsetPercent()
    let soc = info.stateOfCharge

    if let p = pmset {
        print("  顶部状态栏 (pmset):  \(String(format: "%3d%%", p))   (macOS 状态栏 / 系统设置)")
    } else {
        print("  顶部状态栏 (pmset):  ⚠️  读取失败")
    }

    if let s = soc {
        let sBar = makeBar(pct: Double(s), len: 20)
        print("  EC StateOfCharge:    \(String(format: "%3d%%", s))   \(sBar) (EC 内部估算)")
    }

    let calcBar = makeBar(pct: calcPercent, len: 20)
    print("  脚本计算:            \(String(format: "%5.1f%%", calcPercent))   \(calcBar) (= 当前/满电)")

    let p = pmset ?? -1
    let s = soc ?? -1
    if p >= 0 && s >= 0 && abs(Double(p) - calcPercent) < 1 && abs(Double(s) - calcPercent) < 1 {
        print("  ✅ 三者一致")
    } else {
        print("  ⚠️  数据源不一致（EC B1RC 字段可能被 charge-mode 影响，建议重新校准）")
    }
}

/// `charge-mode battery` 专用输出
func printBatteryOnly() {
    let W = 60
    let line = String(repeating: "=", count: W)
    let title = "电池信息"

    print("")
    print(line)
    let pad = max(0, (W - title.count) / 2)
    print(String(repeating: " ", count: pad) + title)
    print(line)

    print("")
    printBatterySection()

    print("")
    print(line)
    print("")
}

/// `charge-mode percent` 专用输出（电量百分比多源对比）
func printPercentOnly() {
    let W = 60
    let line = String(repeating: "=", count: W)
    let title = "电量百分比"

    print("")
    print(line)
    let pad = max(0, (W - title.count) / 2)
    print(String(repeating: " ", count: pad) + title)
    print(line)

    print("")
    printPercentCompareSection()

    print("")
    print(line)
    print("")
}

// MARK: - 电池信息读取

struct BatteryInfo {
    let currentMah: Int
    let fullMah: Int
    let designMah: Int
    let cycleCount: Int
    let voltageMV: Int
    let stateOfCharge: Int?
    let fullyCharged: Bool?
    let batteryState: Int?    // _BST[0] - 原始状态字
    let externalConnected: Bool?  // AC 在位
    let charging: Bool?      // bit 0
    let discharging: Bool?   // bit 1
    let critical: Bool?      // bit 2
    let chargingVoltage: Int?  // mV  - _BST[3]
    let chargingCurrent: Int?  // mA  - _BST[1]
    let instantAmperage: Int?  // mA，正充电/负放电
}

func readBatteryInfo() -> BatteryInfo? {
    var port: mach_port_t = 0
    guard IOMainPort(0, &port) == KERN_SUCCESS else { return nil }

    let matching = IOServiceMatching("AppleSmartBattery")
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(port, matching, &iter) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iter) }

    let svc = IOIteratorNext(iter)
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }

    func readInt(_ svc: io_object_t, _ name: String) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(svc, name as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let v = raw.takeUnretainedValue()
        return (v as? NSNumber)?.intValue
    }

    func readBool(_ svc: io_object_t, _ name: String) -> Bool? {
        guard let raw = IORegistryEntryCreateCFProperty(svc, name as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let v = raw.takeUnretainedValue()
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    guard let cur = readInt(svc, "CurrentCapacity"),
          let full = readInt(svc, "MaxCapacity"),
          let des = readInt(svc, "DesignCapacity"),
          let cyc = readInt(svc, "CycleCount"),
          let vol = readInt(svc, "Voltage") else {
        return nil
    }

    // 解析 _BST[0] 状态字
    // bit 0 (1) = Charging, bit 1 (2) = Discharging, bit 2 (4) = Critical
    let batteryState = readInt(svc, "BatteryStatus")
    let charging = batteryState.map { ($0 & 1) != 0 }
    let discharging = batteryState.map { ($0 & 2) != 0 }
    let critical = batteryState.map { ($0 & 4) != 0 }
    let externalConnected = readBool(svc, "ExternalConnected")

    return BatteryInfo(
        currentMah: cur,
        fullMah: full,
        designMah: des,
        cycleCount: cyc,
        voltageMV: vol,
        stateOfCharge: readInt(svc, "StateOfCharge"),
        fullyCharged: readBool(svc, "FullyCharged"),
        batteryState: batteryState,
        externalConnected: externalConnected,
        charging: charging,
        discharging: discharging,
        critical: critical,
        chargingVoltage: readInt(svc, "ChargingVoltage"),
        chargingCurrent: readInt(svc, "ChargingCurrent"),
        instantAmperage: readInt(svc, "InstantAmperage")
    )
}

// MARK: - 顶部状态栏电量（pmset）

func readPmsetPercent() -> Int? {
    let task = Process()
    task.launchPath = "/usr/bin/pmset"
    task.arguments = ["-g", "batt"]
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
        try task.run()
        task.waitUntilExit()
        guard let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        // pmset 输出格式: "-InternalBattery-0 (id=7143523)\t81%; discharging; 2:07 remaining present: true"
        // 用 ; 分隔百分比和状态
        let pattern = "(\\d+)%\\s*;\\s*(charging|discharging|charged)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: nsRange) else { return nil }
        guard let r = Range(match.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    } catch {
        return nil
    }
}

// MARK: - 进度条工具

func makeBar(pct: Double, len: Int) -> String {
    let filled = max(0, min(len, Int((pct / 100.0) * Double(len))))
    return String(repeating: "█", count: filled)
         + String(repeating: "░", count: len - filled)
}

func setMode(_ svc: io_object_t, conservation: Bool?, rapid: Bool?) {
    print("正在切换充电模式...")

    // 第 1 步：解锁 ECLock（解锁 readEC/writeEC）
    print("  → \(CMD_EC_LOCK) = false（解锁 EC 直接读写）")
    _ = writeProperty(svc, CMD_EC_LOCK, boolToCF(false))

    // 第 2 步：解锁 conservationModeLock（解锁 toggleConservation/toggleRapidCharge）
    print("  → \(CMD_BATTERY_LOCK) = false（解锁 Conservation toggle）")
    _ = writeProperty(svc, CMD_BATTERY_LOCK, boolToCF(false))

    // 第 3 步：从 EC 同步真实状态
    print("  → \(CMD_UPDATE) = true（同步 EC 状态到 ioreg）")
    syncFromEC(svc)
    usleep(500_000)  // 等 0.5s 让 EC 状态同步

    if let c = conservation {
        let cur = cfBoolToBool(readProperty(svc, CMD_CONSERVATION))
        let label = c ? "养护 (上限60%)" : "关闭养护"
        print("  → 当前 ConservationMode = \(cur ?? false), 目标 = \(c)")
        if cur != c {
            print("  → \(CMD_CONSERVATION) = \(c) [\(label)] → 会触发 SBMC(\(c ? 3 : 5))")
            let ok = writeProperty(svc, CMD_CONSERVATION, boolToCF(c))
            if !ok {
                FileHandle.standardError.write("  ✗ 写 ConservationMode 失败\n".data(using: .utf8)!)
            }
        } else {
            print("  → 已为目标值 \(c)，跳过")
        }
    }
    if let r = rapid {
        let cur = cfBoolToBool(readProperty(svc, CMD_RAPID))
        print("  → 当前 RapidChargeMode = \(cur ?? false), 目标 = \(r)")
        if cur != r {
            print("  → \(CMD_RAPID) = \(r) [\(r ? "快充开启" : "快充关闭")] → 会触发 SBMC(\(r ? 7 : 8))")
            let ok = writeProperty(svc, CMD_RAPID, boolToCF(r))
            if !ok {
                FileHandle.standardError.write("  ✗ 写 RapidChargeMode 失败\n".data(using: .utf8)!)
            }
        } else {
            print("  → 已为目标值 \(r)，跳过")
        }
    }

    // 第 4 步：再次同步 EC 状态，确认 toggle 生效
    print("  → 等待 1 秒...")
    usleep(1_000_000)
    print("  → \(CMD_UPDATE) = true（重新同步 EC 状态）")
    syncFromEC(svc)
    usleep(500_000)

    print("\n✓ 命令已发送，请执行 'charge-mode status' 验证。")
}

// MARK: - main

let usage = """
charge-mode — 联想 R7000P 2020H 充电模式切换工具（基于 YogaSMC IdeaVPC）

用法:
  charge-mode status                 三种模式状态 + 当前激活模式
  charge-mode battery                电池容量 / 健康度 / 状态字
  charge-mode percent                电量百分比多源对比（pmset / EC / 脚本）
  charge-mode conservation           切换到养护模式（上限 ~60%）
  charge-mode normal                 切换到常规模式（关闭养护+关闭快充）
  charge-mode rapid                  切换到快充模式
  charge-mode help                   显示此帮助

工作原理: 通过 IORegistryEntrySetCFProperty 写 IdeaVPC 属性，
          YogaSMC kext 自动调用 SBMC(3/5/7/8) 切换 EC 模式。

⚠️  需要 root 权限（sudo）。

例:
  sudo charge-mode conservation
  sudo charge-mode normal
  sudo charge-mode rapid
"""

let args = CommandLine.arguments
if args.count < 2 {
    print(usage)
    exit(1)
}

if args[1] == "help" || args[1] == "-h" || args[1] == "--help" {
    print(usage)
    exit(0)
}

guard let svc = findIdeaVPC() else {
    FileHandle.standardError.write("✗ 找不到 IdeaVPC kext（YogaSMC 没加载？）\n".data(using: .utf8)!)
    FileHandle.standardError.write("  请检查: kextstat | grep -i YogaSMC\n".data(using: .utf8)!)
    exit(1)
}
defer { IOObjectRelease(svc) }

switch args[1] {
case "status":
    printStatus(svc)
case "battery":
    printBatteryOnly()
case "percent":
    printPercentOnly()
case "conservation":
    setMode(svc, conservation: true, rapid: false)
case "normal":
    setMode(svc, conservation: false, rapid: false)
case "rapid":
    setMode(svc, conservation: false, rapid: true)
default:
    print("未知命令: \(args[1])")
    print(usage)
    exit(1)
}