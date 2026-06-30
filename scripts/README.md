# scripts - 通用诊断脚本

跨功能使用的诊断脚本。**单个功能专用的脚本放在 `features/<name>/tests/` 下**。

## 当前脚本

### [ec-diag.sh](ec-diag.sh)
一键收集 EC（Embedded Controller）相关诊断信息：
- macOS 版本、CPU 信息
- pmset 电源管理基线
- 启动参数中 EC/AMFI 相关项
- IOReg EC 节点 dump
- kextstat 关键 kext（VirtualSMC、SMCBatteryManager、AppleACPIEC、YogaSMC）
- OpenCore 版本（如果 EFI 可挂载）

**用法**：
```bash
./ec-diag.sh                          # 默认输出到 logs/$(date)/ec-diag-XXX/
./ec-diag.sh /path/to/output          # 输出到指定目录
```

## 添加新脚本

如果脚本属于某个具体功能（如 charge-mode），放在 `features/<feature>/tests/`。
如果脚本是通用的（如系统级诊断），放在这里。