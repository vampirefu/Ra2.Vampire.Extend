# 间谍自偷 Phobos 兼容设计

## 根因

SPY 能正确消费 `Capture` 规划节点并进入 `CurrentMission=Capture(8)`。Phobos 在同一帧进入其 `0x4D4B43` 钩子；友方 `Infiltrate` 不满足敌方渗透条件，因此 Phobos 清空 `Destination` 并跳到空闲分支。本 DLL 在同一地址的钩子加载顺序靠后，真实 SPY 无法到达。

## 修复

在原版 `Mission_Capture` 函数入口 `0x4D4B20` 添加无冲突前置钩子。此时 `ECX` 是 `FootClass*`。仅当单位是严格间谍、`Target` 为空、`Destination` 是有效己方 Spyable 建筑时，将 `Target` 设置为该建筑。

Phobos 随后在 `0x4D4B43` 看到非空 `Target` 会直接放行，不清空 MegaMission 已设置的建筑 `Destination`。原版继续执行 Capture，抵达建筑后由现有 `0x519FF8` 钩子放行友方渗透。

## 清理与边界

- 删除本 DLL 的 `0x4D4B43` 同址钩子。
- 删除 MegaMission 和规划推进诊断钩子及辅助函数。
- 保留严格间谍判定、`WhatAction` 自偷动作钩子和 `UpdatePosition` 渗透钩子。
- 不清路径、不切换任务、不调用 `SetDestination`、`QueueMission`、`NextMission` 或 `ApproachTarget`。
- 非间谍、敌方建筑、非 Spyable 建筑及已有其他 Target 的情况完全走原版/Phobos 逻辑。

## 验收

源检查完成 RED/GREEN；Release/Debug 零警告零错误；Debug DLL 部署哈希一致；游戏内工程师继续进入建筑，SPY 离开 A、进入建筑并触发渗透。
