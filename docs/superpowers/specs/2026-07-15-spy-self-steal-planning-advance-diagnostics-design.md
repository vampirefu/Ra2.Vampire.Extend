# 间谍自偷规划推进诊断设计

## 目标

确定间谍到达路径点 A 后，规划系统是在调用 `ProceedToNextPlanningWaypoint` 前停止，还是被 `RefreshMegaMission`、`CanUseWaypoint` 或 `TryNextPlanningTokenNode` 的条件拦截。

## 已确认数据流

工程师和 SPY 都收到 `Move(2)` 节点以及指向同一建筑的 `Capture(8)` 节点。最终节点建立时，两者均为 `CurrentMission=Wait(28)`、`QueuedMission=Capture(8)` 且 PlanningToken 非空。SPY 到 A 后没有新的 MegaMission 分派，也没有进入 `Mission_Capture`。

## 诊断点

- `0x709A40`：`ProceedToNextPlanningWaypoint` 入口，`ECX` 为单位。
- `0x709A63`：`RefreshMegaMission` 返回后，`ESI` 为单位，`AL` 为返回值。
- `0x709A71`：`CanUseWaypoint` 返回后，`ESI` 为单位，`AL` 为返回值。
- `0x6385C0`：`TryNextPlanningTokenNode` 入口，`ECX` 为单位。

每个诊断点仅处理工程师和严格间谍，统一记录类型、阶段、返回值、当前/排队任务、目标、目的地、PlanningToken 指针、节点数量、token 标志、路径索引、路径点索引及 NavQueue 数量。

## 安全边界

所有钩子只读取状态并返回 `0`。不设置寄存器，不调用推进函数，不修改任务、目标、路径或 token。

## 验收

源检查完成 RED/GREEN；Release/Debug 零警告零错误；Debug DLL 部署后哈希一致；复测日志能按阶段显示工程师与 SPY 的推进路径。
