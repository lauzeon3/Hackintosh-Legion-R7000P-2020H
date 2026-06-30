/*
 * SSDT-ADP.aml — AC 适配器识别（v1 稳定版）
 *
 * 适用范围: macOS 26 Tahoe (Darwin 25.x)
 *           联想拯救者 R7000P 2020H + OpenCore 1.0.8
 *
 * 作用: 在 \_SB 下重建一个 ACPI0003 设备（ADP0），
 *       代理原生 \_SB.PCI0.LPC0.EC0.ADP0._PSR。
 *
 *       macOS 原生 AppleACPIACAdapter 不会匹配深路径，
 *       重建浅路径后，pmset 就能看到 AC 在位。
 *
 * 历史版本:
 *   v1 (本文件, 编译产物 221 字节): 稳定，AC 唤醒后认领。
 *   v2 (391 字节): 直接读 EC + Notify → 触摸板失灵，已回退。
 *
 * 编译: iasl -p SSDT-ADP SSDT-ADP.dsl
 * 部署:
 *   1. 复制 SSDT-ADP.aml 到 /Volumes/EFI/EFI/OC/ACPI/
 *   2. 编辑 config.plist → ACPI → Add:
 *        Enabled: Yes
 *        Path:    SSDT-ADP.aml
 *      (放在 SSDT-PLUG-ALT.aml 之后)
 *
 * 验证:
 *   ioreg -l -p IOService | grep -A 5 "AppleACPIACAdapter"
 *   pmset -g ac
 */

DefinitionBlock ("", "SSDT", 2, "hack", "ADP0", 0x00000000)
{
    // 引用原生 EC0.ADP0 路径
    External (\_SB.PCI0.LPC0.EC0.ADP0, DeviceObj)
    External (\_SB.PCI0.LPC0.EC0.ADP0._PSR, MethodObj)

    // 隐藏原生 ADP0（路径太深，macOS 无法自动匹配）
    Scope (\_SB.PCI0.LPC0.EC0.ADP0)
    {
        Method (_STA, 0, NotSerialized)
        {
            Return (Zero)
        }
    }

    // 在 \_SB 下重建 ADP0（_HID=ACPI0003 让 macOS 自动绑定）
    Scope (\_SB)
    {
        Device (ADP0)
        {
            Name (_HID, "ACPI0003")

            Method (_STA, 0, NotSerialized) { Return (0x0F) }

            Method (_PSR, 0, NotSerialized)
            {
                Return (\_SB.PCI0.LPC0.EC0.ADP0._PSR ())
            }

            Method (_PCL, 0, NotSerialized)
            {
                Return (Package () { \_SB })
            }
        }
    }
}
