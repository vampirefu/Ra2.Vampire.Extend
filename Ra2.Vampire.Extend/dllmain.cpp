// ===========================================================================
// Ra2.Vampire.Extend - DLL 入口
//
// 本文件仅负责：
//   1. Syringe 握手
//   2. DllMain 中设置日志模块句柄并加载运行时配置
//
// 各功能模块由对应的 .cpp 文件通过 DEFINE_HOOK 静态注册：
//   - SpySelfSteal.cpp   间谍自偷
//   - ChronoAirWall.cpp  超时空步兵下车空气墙修复
// 公共工具：
//   - VampireLog.h       日志宏
//   - VampireConfig.h/cpp 运行时配置
// ===========================================================================

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <string>
#include <algorithm>

#include <Syringe.h>

#include "VampireLog.h"
#include "VampireConfig.h"
#include "SpySelfSteal.h"
#include "ChronoAirWall.h"

// VampireLog::g_Module 由本处在 DLL_PROCESS_ATTACH 时设置（仅 Debug 构建使用）。
#ifdef _DEBUG
HMODULE VampireLog::g_Module = nullptr;
#endif

// ===========================================================================
// Syringe 握手接口
// ===========================================================================
SYRINGE_HANDSHAKE(pInfo)
{
    if (pInfo)
    {
        std::string message = "Ra2.Vampire.Extend";
        int maxCopy = pInfo->cchMessage > 0 ? pInfo->cchMessage - 1 : 0;
        int toCopy = static_cast<int>(std::min<size_t>(message.size(), maxCopy));
        if (toCopy > 0 && pInfo->Message)
            std::copy(message.begin(), message.begin() + toCopy, pInfo->Message);
        if (pInfo->Message)
            pInfo->Message[toCopy] = '\0';
        return S_OK;
    }
    return E_POINTER;
}

// ===========================================================================
// DLL 入口
// ===========================================================================
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    if (ul_reason_for_call == DLL_PROCESS_ATTACH)
    {
#ifdef _DEBUG
        VampireLog::g_Module = hModule;
#endif
        VAMP_LOG("DllMain - DLL_PROCESS_ATTACH, hModule=0x%p", hModule);

        // 加载运行时配置（Ra2.Vampire.Extend.ini，位于 gamemd.exe 同目录）
        VampireConfig::Load();

        // 各功能模块初始化（当前钩子由 DEFINE_HOOK 静态注册，Init 为空操作）
        SpySelfSteal::Init();
        ChronoAirWall::Init();
    }
    return TRUE;
}
