# 间谍自偷 MegaMission 诊断设计

## 目标

确认工程师和间谍在“路径点 A → 残血己方 Spyable 建筑”操作中分别收到的 MegaMission 数据，定位间谍停止于 A 的真实命令分派层。

## 证据

- 延迟目标版本确实依次执行了 `Mission_Capture` 入口和 `0x4D4BC7` 钩子，但间谍仍停在 A。
- `WhatAction` 日志对象为 `0x250F9190`，`Mission_Capture` 日志对象为 `0x250F8A98`；它们不是同一单位。
- 没有出现 `UpdatePosition` 渗透日志。
- AGWar 同时加载 Ares、Phobos 和 Ra2.Vampire.Extend；Phobos 在 `0x4D4B43` 也有 `Mission_Capture` 钩子。
- Phobos 将间谍识别为 `Agent && Infiltrate`，工程师单独使用 `Engineer`；当前项目仅用 `Infiltrate`，在模组规则中可能误分类。

## 设计

1. 将项目的间谍判定收紧为 `Agent && Infiltrate && !Engineer`。
2. 保留 `WhatAction` 自偷动作钩子和 `UpdatePosition` 最终渗透钩子。
3. 将 `0x4D4B43` 钩子改为严格间谍的只读日志，不再设置或清理任何目标、目的地、路径或任务。
4. 移除失败的 `0x4D4BC7` 延迟目标钩子。
5. 在 `0x4C7462` 增加只读 MegaMission 日志钩子。该地址的 Phobos 参考确认 `EDI` 是接收命令的 `TechnoClass*`，`ESI` 是 `EventClass*`。
6. 仅记录工程师和严格间谍，字段包括类型 ID、对象地址、唯一 ID、兵种标志、事件 Mission/Target/Destination/Follow、`IsPlanningEvent`、当前/排队任务、PlanningToken、路径索引、路径点索引和 NavQueue 数量。

## 安全边界

诊断钩子始终返回 `0`，不调用 `SetTarget`、`SetDestination`、`QueueMission`、`NextMission`、`ClearNavigationList` 或 `ApproachTarget`。本轮不尝试修复运行时行为。

## 验收

- PowerShell 源检查先因缺少诊断钩子失败，再在实现后通过。
- Win32 Release/Debug 均以零错误构建。
- Debug DLL 部署后源/目标 SHA256 相同。
- 游戏内复测日志能显示工程师和间谍各自的 MegaMission 行。
