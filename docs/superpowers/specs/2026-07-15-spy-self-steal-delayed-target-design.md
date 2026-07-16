# 间谍自偷延迟目标注入设计

## 目标

在 AGWar 1.3.1 的尤里的复仇环境中，工程师和间谍共同执行“路径点 A → 残血己方可渗透建筑”时，工程师继续进入建筑维修，间谍也从 A 点继续前往建筑并触发自偷效果。

## 已确认现象与证据

- 当前安全基线下，工程师可以进入建筑，间谍稳定停在路径点 A。
- 运行日志显示间谍首次进入 `Mission_Capture` 时 `Target == nullptr`，而 `Destination` 已经是目标建筑。
- 当前 `0x4D4B43` 钩子立即执行 `SetTarget(pBld)`。
- AGWar 1.3.1 `gamemd.exe` 的原版代码在 `0x4D4B57` 检测到非空 `Target` 后跳至 `0x4D4C14`，从而跳过 `0x4D4BB4` 的虚函数 `SetDestination(Destination, true)`。
- YRPP 的 `InfantryTypeClass` 布局确认原版在 `+0xEC2` 检查的是 `Infiltrate`。间谍保持空 `Target` 时会自然进入 `0x4D4BB4`，无需手动重建路径或切换任务。

## 设计

保留 `WhatAction` 与 `UpdatePosition` 两个现有钩子。修改 `Mission_Capture` 的目标注入时序：

1. `0x4D4B43` 只识别“己方间谍 + 己方 Spyable 建筑”场景并记录日志，不再提前设置 `Target`。
2. 原版代码根据 `Infiltrate` 执行 `0x4D4BB4` 的 `SetDestination`，由游戏自身维护路径点链和移动状态。
3. 在紧随其后的 `0x4D4BC7` 新增钩子；仅当 `Target` 仍为空且 `Destination` 是符合条件的自偷建筑时，执行 `SetTarget(pBld)`。
4. 返回原版 `0x4D4BC7`，使随后的空目标检查看到目标已经存在，避免进入空闲状态。

该设计不调用 `ClearNavigationList`、`ApproachTarget`、`QueueMission`、`NextMission`，也不手动调用 `SetDestination`，从而避免此前对工程师路径链造成的副作用。

## 诊断与测试

- 静态 PowerShell 回归测试要求入口钩子不再包含早期 `SetTarget`，并要求存在 `0x4D4BC7` 延迟钩子。
- 测试继续禁止所有已确认会破坏路径或任务状态的操作。
- Debug 日志分别记录“等待原版设置目的地”和“原版设置目的地后注入目标”，便于游戏内复测确认执行顺序。

## 构建与部署

- 分别构建 Win32 Release 和 Win32 Debug。
- 部署前确认没有 `gamemd`、`Syringe` 或 AGWar 进程。
- 备份现有游戏 DLL 和日志，将 Debug DLL 复制到 AGWar 1.3.1 根目录，并比较源/目标 SHA256。

## 验收标准

- 自动源代码检查通过。
- Release 与 Debug 均构建成功且无编译错误。
- 部署 DLL 的 SHA256 与 Debug 构建产物一致。
- 游戏内执行路径点 A → 残血己方 Spyable 兵营时，工程师可以进入，间谍不再停在 A，并最终触发渗透。
