// ===========================================================================
// VampireConfig - 运行时配置实现
// ===========================================================================

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cstring>

#include "VampireConfig.h"
#include "VampireLog.h"

namespace VampireConfig
{
    bool SelfStealEnabled = true;
    bool ChronoAirWallFixEnabled = true;

    static void BuildConfigPath(char* outPath, size_t outSize)
    {
        char exePath[MAX_PATH] = {};
        GetModuleFileNameA(nullptr, exePath, MAX_PATH);

        char* slash = std::strrchr(exePath, '\\');
        size_t prefixLen = slash ? static_cast<size_t>(slash + 1 - exePath) : 0;

        static const char name[] = "Ra2.Vampire.Extend.ini";
        size_t need = prefixLen + sizeof(name); // 含 '\0'
        if (need > outSize)
        {
            outPath[0] = '\0';
            return;
        }

        std::memcpy(outPath, exePath, prefixLen);
        std::memcpy(outPath + prefixLen, name, sizeof(name));
    }

    void Load()
    {
        char path[MAX_PATH] = {};
        BuildConfigPath(path, MAX_PATH);

        // GetPrivateProfileIntA 缺键时返回默认值，文件缺失同样返回默认值
        SelfStealEnabled = GetPrivateProfileIntA("Vampire", "SelfSteal", 1, path) != 0;
        ChronoAirWallFixEnabled = GetPrivateProfileIntA("Vampire", "ChronoAirWallFix", 1, path) != 0;

        VAMP_LOG("VampireConfig loaded: SelfSteal=%d ChronoAirWallFix=%d path=%s",
            SelfStealEnabled ? 1 : 0,
            ChronoAirWallFixEnabled ? 1 : 0,
            path);
    }
}
