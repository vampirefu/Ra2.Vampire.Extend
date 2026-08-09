#pragma once
// ===========================================================================
// 超时空步兵下车空气墙修复 (Chrono Infantry Dismount Air-Wall Fix)
//
// 问题：Locomotor=Teleport 的步兵从载具下车时，原版将其放置在载具所在
//   单元格（超时空单位允许共享单元格），Teleport 运动器的占位标记会在
//   该格留下无法清除的"幽灵空气墙"，永久阻挡其他单位通行。
//
// 修复（源头拦截，对应设计文档入口1：D 键手动卸载）：
//   拦截 UnitClass::Mi_Unload（0x73D63B，Phobos 已验证的钩子点），当首位
//   乘客为超时空步兵时：
//     - 以载具所在格为原点，8 方向邻格扫描（IsCellOccupied == OK/MovingBlock）；
//     - 找到可用邻格：移除乘客 + Unlimbo 至邻格（复用 Phobos TechnoExt::
//       EjectSurvivor 的非伞降重定位序列，正确建立新占位，不残留幽灵标记）；
//     - 四周全堵：跳过本帧卸载，步兵留在车内（不强制原地下车触发 BUG）。
//   非超时空步兵：放行原版逻辑。
//
// 超时空仪隔离：本模块仅在 Mi_Unload（载具卸载）触发，不进入超武传送链路、
//   不读取超时空仪激活函数，零干扰。单位自主超时空移动属于 Motion 循环，
//   与本钩子作用域完全切割。
//
// 兵种判定：仅读取 TechnoTypeClass::Locomotor 静态 CLSID，与
//   LocomotionClass::CLSIDs::Teleport 比较，不读取运行时 Motion 实例，
//   规避爆炸瞬间运动器延迟切换导致的漏判。
//
// 注：爆炸弹射幸存者（设计入口2）由 Ares.dll 路由，Phobos 的 EjectRandomly
//   已采用与本模块一致的 8 邻格扫描；本模块保持解耦，后续如需独立覆盖原生
//   弹射路径，复用 IsChronoInfantry / FindClearNeighborCell 即可扩展。
// ===========================================================================

#ifndef CHRONO_AIR_WALL_H
#define CHRONO_AIR_WALL_H

namespace ChronoAirWall
{
    // 预留初始化入口（当前钩子由 DEFINE_HOOK 静态注册，无需动态初始化）。
    inline void Init() {}
}

#endif // CHRONO_AIR_WALL_H
