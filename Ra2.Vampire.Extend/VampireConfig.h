#pragma once
// ===========================================================================
// VampireConfig - 运行时配置（Ra2.Vampire.Extend.ini）
//
// INI 位于 gamemd.exe 同目录，DllMain 加载时读取一次。
// 模块化设计：所有功能开关集中于此，各 Hook 模块按需查询，互不耦合。
//
//   [Vampire]
//   SelfSteal=1            ; 间谍自偷（默认开启）
//   ChronoAirWallFix=1     ; 超时空步兵下车空气墙修复（默认开启）
// ===========================================================================

#ifndef VAMPIRE_CONFIG_H
#define VAMPIRE_CONFIG_H

namespace VampireConfig
{
    extern bool SelfStealEnabled;
    extern bool ChronoAirWallFixEnabled;

    // 读取 gamemd.exe 同目录下的 Ra2.Vampire.Extend.ini。
    // 缺键 / 缺文件时返回默认值（全部开启）。
    void Load();
}

#endif // VAMPIRE_CONFIG_H
