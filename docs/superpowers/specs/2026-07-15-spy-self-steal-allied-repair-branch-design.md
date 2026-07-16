# 间谍自偷友军维修分支修复设计

## 背景与根因

当前实现已经让规划路径中的间谍通过路径点 A，并在 `FootClass::Mission_Capture` 进入 Phobos 钩子前保留友军兵营目标。但最新日志没有出现 `0x519FF8` 的 `UpdatePosition` 渗透日志。

AGWar 1.3.1 的 `gamemd.exe` 反汇编表明：间谍抵达友军建筑后，`0x519D4E` 的 `HouseClass::IsAlliedWith` 返回真，`0x519D55` 随即跳到 `0x519FA2`。残血建筑再从 `0x519FB7` 跳到 `0x519FEC` 的维修处理，最终绕过 `0x519FF8` 渗透入口。这是间谍到达兵营却不进入的直接原因。

## 修改范围

只修改 `Ra2.Vampire.Extend`，不修改 Phobos、Ares、AGWar 配置或游戏本体。

在 `0x519D53` 增加覆盖 8 字节的钩子，对应完整指令：

```asm
test al, al
jne 0x519FA2
```

此处 `ESI` 是 `InfantryClass*`，`EDI` 是 `BuildingClass*`。钩子仅在以下条件全部成立时跳到现有 `0x519FF8` 渗透门：

- 单位满足严格间谍判定：`Agent && Infiltrate && !Engineer`；
- 目标是有效的 `Spyable` 建筑；
- 单位所有者与建筑所有者结盟，包括同一阵营。

其他情况返回原控制流，不改变原版或 Phobos 行为。现有 `0x519FF8` 钩子继续进行同一场景校验，再转到 `0x51A002`；Phobos 在 `0x51A002` 的 `SpiedBy`、`SpyAsHouse`、`SpyAsInfantry` 事件钩子因此仍会执行。

## 状态与兼容性约束

新钩子不得设置或清除 `Target`、`Destination`、路径点或任务，不得直接调用 `BuildingClass::InfiltratedBy`。工程师维修/进入流程、敌方间谍渗透、非间谍单位和非 `Spyable` 建筑必须保持原行为。

Phobos 当前没有在 `0x519D53` 安装钩子；其 `0x51A002` 钩子保持不变。

## 验证

1. 先扩展静态检查，要求存在 `0x519D53`、8 字节覆盖、`ESI`/`EDI` 取值、严格场景校验以及跳转到 `0x519FF8`，并禁止路径/任务变更；修改实现前该检查必须失败。
2. 实现单一钩子后运行静态检查。
3. 分别构建 Win32 Release 和 Debug，要求零错误。
4. 确认 AGWar、`gamemd.exe` 和 Syringe 均未运行，备份现有 DLL 与日志后部署 Debug DLL，并核对 SHA256。
5. 游戏中复测：工程师和间谍依次经过 A；工程师进入残血友军兵营；间谍进入同一兵营并触发渗透；游戏不崩溃。
