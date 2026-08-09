#pragma once
// ===========================================================================
// VampireLog - 公共日志工具
//
// 提供 VAMP_LOG 宏，Debug 构建写入 OutputDebugString 与同目录日志文件，
// Release 构建编译为空操作，零开销。
// 各功能模块通过 #include "VampireLog.h" 共享同一日志通道。
// ===========================================================================

#ifndef VAMPIRE_LOG_H
#define VAMPIRE_LOG_H

#include <windows.h>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <stdlib.h>

namespace VampireLog
{
    // 由 dllmain.cpp 在 DLL_PROCESS_ATTACH 时设置，日志据此定位 DLL 同目录。
    // Release 构建下日志整体被禁用，此变量不会被引用。
    extern HMODULE g_Module;
}

#ifdef _DEBUG
namespace VampireLog
{
    inline void VampLog(const char* fmt, ...)
    {
        char message[512];
        va_list args;
        va_start(args, fmt);
        _vsnprintf_s(message, _countof(message), _TRUNCATE, fmt, args);
        va_end(args);

        char line[640];
        _snprintf_s(line, _countof(line), _TRUNCATE, "[Vampire.Extend] %s\r\n", message);
        OutputDebugStringA(line);

        if (!VampireLog::g_Module)
            return;

        char path[MAX_PATH] {};
        if (!GetModuleFileNameA(VampireLog::g_Module, path, _countof(path)))
            return;

        char* fileName = std::strrchr(path, '\\');
        fileName = fileName ? fileName + 1 : path;
        strcpy_s(fileName, static_cast<size_t>(_countof(path) - (fileName - path)), "Ra2.Vampire.Extend.log");

        HANDLE const hFile = CreateFileA(
            path,
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);

        if (hFile == INVALID_HANDLE_VALUE)
            return;

        DWORD written = 0;
        WriteFile(hFile, line, static_cast<DWORD>(std::strlen(line)), &written, nullptr);
        CloseHandle(hFile);
    }
}
#define VAMP_LOG(...) VampireLog::VampLog(__VA_ARGS__)
#else
#define VAMP_LOG(...) do { } while(0)
#endif

#endif // VAMPIRE_LOG_H
