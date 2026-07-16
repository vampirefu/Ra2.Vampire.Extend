# 间谍自偷重新激活 Capture 目的地设计

## 已确认根因

最新游戏日志只出现 `Mission_Capture prehook`，没有出现 `0x519D53` 或 `0x519FF8` 的抵达日志。上一份完整转储同时确认 AGWar 的 SPY 类型在 `+0xEC3` 为零；只要它真正进入 `InfantryClass::UpdatePosition` 的建筑抵达段，原版就会直接跳到 `0x519FF8`。因此问题不在末端渗透分支，而在更早的 Capture 目的地初始化。

规划事件切换到 `Mission::Capture` 时，SPY 的 `Target` 为空、`Destination` 已是友军兵营。当前 `0x4D4B20` 前钩子只补上 `Target`，保留非空 `Destination`。Phobos 在 `0x4D4B43` 因 Target 非空而放行，但原版随后在 `0x4D4B57` 因 Destination 非空跳过 `0x4D4BB4` 的 `SetDestination(Target, true)`。SPY 于是沿规划目的地走近建筑，却没有重新建立 Capture 所需的正常进入状态。

## 架构替换

只修改 `Ra2.Vampire.Extend`，不修改 Phobos、Ares、AGWar 配置或游戏本体。

保留现有 `0x4D4B20` 前钩子及其严格场景判断。仅当以下条件全部成立时执行一次重新激活：

- 对象是 `InfantryClass`；
- 类型满足 `Agent && Infiltrate && !Engineer`；
- `Target` 为空；
- `Destination` 是有效的友军 `Spyable` 建筑。

钩子保存建筑指针后依次执行：

```cpp
pThis->SetDestination(nullptr, false);
pThis->SetTarget(pBld);
```

调用顺序不可交换：先清空规划 Destination，再设置 Target，确保 Phobos 看到非空 Target；随后原版在 `0x4D4B57` 看到空 Destination，并在 `0x4D4BB4` 自行调用 `SetDestination(Target, true)`，由游戏原生逻辑重建移动和建筑进入状态。因为后续帧 Target 已非空，前钩子不会重复重置 Destination。

## 清理与兼容性

删除 `0x519D53` 钩子及其专项静态检查。该地址位于 `Fraidycat` 非零分支，AGWar SPY 不会经过它；保留它只会扩大对工程师和其他步兵的影响范围。

保留以下现有行为：

- `0x51EE4E` 允许严格间谍对友军 `Spyable` 建筑获得 Capture 动作；
- `0x4D4B20` 在 Phobos 之前处理一次 Capture 重新激活；
- `0x519FF8` 在 SPY 真正抵达后放行友军渗透；
- Phobos 的 `0x4D4B43` 和 `0x51A002` 钩子不做任何修改。

不得调用 `QueueMission`、`NextMission`、`ClearNavigationList`、`ApproachTarget` 或 `BuildingClass::InfiltratedBy`。

## 验证

1. 先修改 PowerShell 静态检查：要求 `SetDestination(nullptr, false)` 出现在 `SetTarget(pBld)` 之前，要求删除 `0x519D53`，并继续禁止其他路径/任务操作；实现修改前检查必须失败。
2. 实现一次性 Destination 重新激活并删除无效钩子后，静态检查必须通过。
3. 重新构建 Win32 Release 和 Debug，构建后再次运行静态检查。
4. 确认 AGWar 目录内无运行进程，备份当前 DLL 和日志，部署 Debug DLL并核对 SHA256；Phobos 已跟踪和暂存差异必须为空。
5. 游戏内复测“工程师和间谍 → A → 残血友军 Spyable 兵营”。工程师必须正常进入且不崩溃；间谍必须经过 A、进入同一建筑并触发渗透。
