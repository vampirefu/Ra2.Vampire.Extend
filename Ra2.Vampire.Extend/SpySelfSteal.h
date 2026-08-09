#pragma once
// ===========================================================================
// 间谍自偷 (Spy Self-Stealing) for Yuri's Revenge
//
// 模仿共和国之辉的机制：
//   1. 用单位强制攻击己方建筑使其残血
//   2. 选中工程师和间谍，让工程师更靠近建筑
//   3. 通过路径功能让工程师去修建筑
//   4. 间谍会跟着工程师一起进入建筑进行渗透
//
// 实现原理：
//   原版YR中间谍只能渗透敌方建筑。本模块通过多个钩子解除这一限制，
//   允许间谍对己方/盟友的Spyable建筑执行渗透。
//
// 模块接口：
//   SpySelfSteal::Init() 由 dllmain 调用（当前为空，钩子静态注册）。
//   其余均为内部实现，由 DEFINE_HOOK 静态绑定到 Syringe。
// ===========================================================================

#ifndef SPY_SELF_STEAL_H
#define SPY_SELF_STEAL_H

namespace SpySelfSteal
{
    // 预留初始化入口（当前钩子由 DEFINE_HOOK 静态注册，无需动态初始化）。
    inline void Init() {}
}

#endif // SPY_SELF_STEAL_H
