# Ra2.Vampire.Extend

尤里的复仇（Yuri's Revenge）扩展 DLL，通过 Syringe 注入 gamemd.exe，为游戏添加额外机制。

## 功能

### 间谍自偷（Spy Self-Stealing）

模仿共和国之辉的经典机制，允许间谍渗透己方或盟友的 **Spyable** 建筑，获得与渗透敌方建筑相同的效果。

**操作步骤：**

1. 用单位强制攻击己方建筑使其残血
2. 选中工程师和间谍，让工程师更靠近建筑
3. 通过路径功能（Waypoint）让工程师去修建筑
4. 间谍会跟着工程师一起进入建筑进行渗透

**渗透效果（与渗透敌方建筑一致）：**

| 建筑类型 | 效果 |
|---------|------|
| 兵营（Factory=InfantryType） | `BarracksInfiltrated` — 获得敌方步兵科技 |
| 战车工厂（Factory=UnitType） | `WarFactoryInfiltrated` — 获得敌方载具科技 |
| BuildTech 建筑 | `SideXTechInfiltrated` — 获得对应阵营科技 |
| 发电建筑 | `PowerOutage` — 己方断电（与渗透敌方电厂效果相同） |

> **注意：** 间谍自偷发电建筑会导致己方断电，请谨慎操作！

## 实现原理

原版 YR 中间谍只能渗透敌方建筑，存在两层限制：

1. **鼠标光标判定**：玩家房屋的 `[0xEBE]` 标志为 0，导致代码跳过所有间谍逻辑；即使 `[0xEBE]` 不为 0，`IsAlliedWith` 检查也会阻止对盟友建筑返回 Capture 动作
2. **渗透效果执行**：`InfiltratedBy` 函数内部检查所有权/敌对关系，对己方/盟友建筑跳过所有效果分支

本插件通过多个钩子解除这两层限制，并处理路径规划、单元格占用、工程师分支跳过等边界情况。

## 钩子清单

| 钩子名称 | 地址 | 目标函数 | 作用 |
|---------|------|---------|------|
| `InfantryClass_WhatAction_SpySelfSteal` | `0x51EE4E` | `InfantryClass::MouseOverObject` | 绕过 `[0xEBE]` 和 `IsAlliedWith` 检查，允许间谍对己方 Spyable 建筑显示 Capture 光标 |
| `EventClass_Execute_MegaMission_AuthorizeSpySelfStealPath` | `0x4C7462` | `EventClass::Execute` | 在规划 Capture 命令执行时记录授权，绑定间谍与目标建筑 |
| `TechnoClass_TryNextPlanningTokenNode_Log` | `0x6385C0` | `TechnoClass::TryNextPlanningTokenNode` | 规划路径推进时授权自偷并准备最终 Capture 节点 |
| `FootClass_Mission_Capture_PrepareSpySelfSteal` | `0x4D4B20` | `FootClass::Mission_Capture` | Capture 任务开始前重新激活 Destination 和 Target，使 Phobos 放行间谍自偷 |
| `InfantryClass_IsCellOccupied_AllowSpySelfStealDestination` | `0x51BFD2` | `InfantryClass::IsCellOccupied` | 允许间谍自偷目的地单元格通过占用性检查 |
| `InfantryClass_UpdatePosition_SpySelfSteal_SkipEngineerPath` | `0x519B58` | `InfantryClass::UpdatePosition` | 间谍到达建筑后跳过工程师修建筑分支，直接触发渗透逻辑 |
| `BuildingClass_InfiltratedBy_ForceSelfStealFlag` | `0x45723C` | `BuildingClass::InfiltratedBy` | 强制渗透效果标志为 1，绕过友方/盟友检查，使所有渗透效果正常执行 |

## 使用方法

### 前置条件

- [Syringe](https://github.com/CnCNet/syringe) — DLL 注入器
- [YRpp](https://github.com/CnCNet/YRpp) — 尤里的复仇 C++ 头文件和库
- [Phobos](https://github.com/Phobos-developers/Phobos) — 兼容（本插件的 `Mission_Capture` 钩子在 Phobos 之前执行）

### 安装

1. 编译项目生成 `Ra2.Vampire.Extend.dll`
2. 将 DLL 放置在游戏目录下
3. 通过 Syringe 启动游戏并加载本 DLL：

```bash
syringe.exe gamemd.exe -RA2.Vampire.Extend.dll
```

或在 CnCNet 启动配置中添加本 DLL。

### 游戏内操作

1. 进入游戏对局
2. 训练间谍和工程师
3. 用单位攻击己方建筑使其受损（血条变黄/红）
4. 选中工程师和间谍，**让工程师更靠近目标建筑**（路径系统会让离建筑更近的单位优先行动）
5. 使用路径功能（Waypoint）让工程师去修建筑
6. 间谍会跟随工程师进入建筑，触发渗透效果

### 调试日志

Debug 编译会输出详细日志到 DLL 同目录下的 `Ra2.Vampire.Extend.log`，包含：

- 规划路径推进诊断
- Capture 命令授权状态
- UpdatePosition 移动和到达边界
- InfiltratedBy 渗透效果执行

Release 编译不输出日志。

## 编译

使用 Visual Studio 打开 `Ra2.Vampire.Extend.sln`，确保 YRpp 头文件路径已正确配置。

- **Debug** 配置：启用 `VAMP_LOG` 诊断日志
- **Release** 配置：禁用日志，无额外开销

## 兼容性

- 兼容 **Phobos**：`Mission_Capture` 钩子（`0x4D4B20`）位于 Phobos 钩子（`0x4D4B43`）之前，两者互不干扰
- 兼容 **Ares**：无地址冲突
- 仅支持 `gamemd.exe`（尤里的复仇 1.001）

## 许可证

请参阅 [LICENSE](LICENSE) 文件。
