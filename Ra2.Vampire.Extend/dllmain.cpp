#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <string>
#include <algorithm>
#include <cstdio>
#include <cstdarg>
#include <cstring>

// YRpp headers use 'byte' (lowercase) which is not a standard C++ type
using byte = unsigned char;

#include <Syringe.h>
// Include class headers first so AbstractTypeClass is defined before Cast.h
#include <InfantryClass.h>
#include <BuildingClass.h>
#include <CellClass.h>
#include <HouseClass.h>
#include <RulesClass.h>
#include <Helpers/Macro.h>
#include <Helpers/Cast.h>

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
//   原版YR中间谍只能渗透敌方建筑。本插件通过三个钩子解除这一限制，
//   允许间谍对己方/盟友的Spyable建筑执行渗透。
//
// 钩子点：
//   1. 0x51EE4E - InfantryClass::MouseOverObject   (鼠标光标动作判定)
//   2. 0x4D4B20 - FootClass::Mission_Capture       (Phobos前重新激活目的地)
//   3. 0x519FF8 - InfantryClass::UpdatePosition    (到达后触发渗透)
// ===========================================================================

#ifdef _DEBUG
static HMODULE gVampireModule = nullptr;

static void VampLog(const char* fmt, ...)
{
    char message[512];
    va_list args;
    va_start(args, fmt);
    _vsnprintf_s(message, _countof(message), _TRUNCATE, fmt, args);
    va_end(args);

    char line[640];
    _snprintf_s(line, _countof(line), _TRUNCATE, "[Vampire.Extend] %s\r\n", message);
    OutputDebugStringA(line);

    if (!gVampireModule)
        return;

    char path[MAX_PATH] {};
    if (!GetModuleFileNameA(gVampireModule, path, _countof(path)))
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

#define VAMP_LOG(...) VampLog(__VA_ARGS__)
#else
#define VAMP_LOG(...) do { } while(0)
#endif

static bool IsCandidateSpy(InfantryClass* pThis)
{
    return pThis && pThis->Type
        && pThis->Type->Agent
        && pThis->Type->Infiltrate
        && !pThis->Type->Engineer;
}

// ---------------------------------------------------------------------------
// 辅助函数：判断是否为"间谍自偷"场景
// 条件：单位是严格间谍(Agent + Infiltrate) + 目标是Spyable建筑 + 双方是盟友/同一阵营
// ---------------------------------------------------------------------------
static bool IsSpySelfStealScenario(InfantryClass* pThis, BuildingClass* pBuilding)
{
    if (!pThis || !pBuilding)
        return false;

    // 必须是间谍类型
    if (!pThis->Type || !pThis->Type->Infiltrate)
        return false;

    // 建筑必须可被渗透
    if (!pBuilding->Type || !pBuilding->Type->Spyable)
        return false;

    // 必须是己方或盟友的建筑（这是"自偷"的核心条件）
    if (!pThis->Owner || !pThis->Owner->IsAlliedWith(pBuilding->Owner))
        return false;

    return true;
}

// ---------------------------------------------------------------------------
// 全局上下文：从 0x519B58 钩子传递到 InfiltratedBy 钩子
// 单线程游戏，0x519B58 跳转到 0x51A002 后同步调用 InfiltratedBy，
// 中间不会有其他 InfiltratedBy 调用插入。
// ---------------------------------------------------------------------------
static InfantryClass* g_SpySelfSteal_Infantry = nullptr;
static BuildingClass* g_SpySelfSteal_Building = nullptr;

static void ClearSpySelfStealInfiltrationContext()
{
    g_SpySelfSteal_Infantry = nullptr;
    g_SpySelfSteal_Building = nullptr;
}

static bool ApplySpySelfStealFactoryEffect(InfantryClass* pThis, BuildingClass* pBuilding)
{
    if (!pThis || !pThis->Owner || !pBuilding || !pBuilding->Type)
        return false;

    switch (pBuilding->Type->Factory)
    {
    case AbstractType::InfantryType:
        pThis->Owner->BarracksInfiltrated = true;
        pThis->Owner->RecheckTechTree = true;
        VAMP_LOG("Spy self-steal manual effect: BarracksInfiltrated=1");
        return true;

    case AbstractType::UnitType:
        pThis->Owner->WarFactoryInfiltrated = true;
        pThis->Owner->RecheckTechTree = true;
        VAMP_LOG("Spy self-steal manual effect: WarFactoryInfiltrated=1");
        return true;

    default:
        VAMP_LOG(
            "Spy self-steal manual effect: no factory effect for factory=%d",
            static_cast<int>(pBuilding->Type->Factory));
        return false;
    }
}

static bool ApplySpySelfStealBuildTechEffect(InfantryClass* pThis, BuildingClass* pBuilding)
{
    if (!pThis || !pThis->Owner || !pBuilding || !pBuilding->Type || !RulesClass::Instance)
        return false;

    if (RulesClass::Instance->BuildTech.FindItemIndex(pBuilding->Type) >= 0)
    {
        auto const pSideHouse = pBuilding->Owner ? pBuilding->Owner : pThis->Owner;
        auto const sideIndex = pSideHouse && pSideHouse->Type ? pSideHouse->Type->SideIndex : pThis->Owner->SideIndex;

        switch (sideIndex)
        {
        case 0:
            pThis->Owner->Side0TechInfiltrated = true;
            break;

        case 1:
            pThis->Owner->Side1TechInfiltrated = true;
            break;

        default:
            pThis->Owner->Side2TechInfiltrated = true;
            break;
        }

        pThis->Owner->RecheckTechTree = true;
        VAMP_LOG("Spy self-steal manual effect: BuildTech side=%d", sideIndex);
        return true;
    }

    return false;
}

static bool ApplySpySelfStealPowerEffect(InfantryClass* pThis, BuildingClass* pBuilding)
{
    if (!pThis || !pThis->Owner || !pBuilding || !pBuilding->Type || !RulesClass::Instance)
        return false;

    if (RulesClass::Instance->BuildPower.FindItemIndex(pBuilding->Type) >= 0
        || pBuilding->Type->PowerBonus > pBuilding->Type->PowerDrain)
    {
        reinterpret_cast<void(__thiscall*)(HouseClass*, int)>(0x50BC90)(pThis->Owner, RulesClass::Instance->SpyPowerBlackout);
        VAMP_LOG(
            "Spy self-steal manual effect: PowerOutage duration=%d",
            RulesClass::Instance->SpyPowerBlackout);
        return true;
    }

    return false;
}

static void TriggerSpySelfStealInfiltration(InfantryClass* pThis, BuildingClass* pBuilding)
{
    if (!pThis || !pBuilding || !pThis->Owner)
        return;

    g_SpySelfSteal_Infantry = pThis;
    g_SpySelfSteal_Building = pBuilding;

    VAMP_LOG(
        "UpdatePosition: spy self-steal, calling BuildingClass::InfiltratedBy directly this=%p building=%p owner=%p",
        pThis,
        pBuilding,
        pThis->Owner);

    reinterpret_cast<void(__thiscall*)(BuildingClass*, HouseClass*)>(0x4571E0)(pBuilding, pThis->Owner);

    if (g_SpySelfSteal_Infantry || g_SpySelfSteal_Building)
    {
        VAMP_LOG("UpdatePosition: spy self-steal, direct InfiltratedBy returned without flag hook");
        ClearSpySelfStealInfiltrationContext();
    }

    ApplySpySelfStealFactoryEffect(pThis, pBuilding);
    ApplySpySelfStealBuildTechEffect(pThis, pBuilding);
    ApplySpySelfStealPowerEffect(pThis, pBuilding);
}

// ===========================================================================
// 钩子1: InfantryClass::MouseOverObject (WhatAction)
// 地址: 0x51EE4E, 大小: 0x6
// 原始指令: mov eax, [edi + 0x6c0]  (加载 controlling house)
//
// 关键：钩子必须放在 [0xEBE] 检查(0x51EE54)之前！
//   0x51EE4E: mov eax, [edi + 0x6c0]   ; controlling house  ← 本钩子
//   0x51EE54: mov cl, [eax + 0xebe]    ; spy capability flag
//   0x51EE5A: test cl, cl
//   0x51EE5C: je 0x51f095              ; [0xEBE]==0 时跳过所有间谍逻辑
//   0x51EE62: cmp ebp, 5               ; 旧钩子位置（[0xEBE]==0 时不可达）
//
// 原版逻辑：[0xEBE] 是间谍能力标志。玩家房屋的 [0xEBE] 通常为 0，
//   导致代码从 0x51EE5C 直接跳到 0x51F095，完全跳过间谍渗透逻辑。
//   即使 [0xEBE]!=0，代码还会检查 IsAlliedWith，对盟友建筑不返回 Capture。
//
// 我们的逻辑：如果是间谍自偷场景，直接跳到渗透设置代码(0x51EEED)，
//   绕过 [0xEBE] 检查和 IsAlliedWith 检查。
//   0x51EEED 设置 action=9(Capture) 并计算进入坐标。
// ===========================================================================
DEFINE_HOOK(0x51EE4E, InfantryClass_WhatAction_SpySelfSteal, 0x6)
{
    enum { SkipToInfiltrationSetup = 0x51EEED };

    GET(InfantryClass*, pThis, EDI);
    GET(AbstractClass*, pTarget, ESI);

    // 检查目标是否为建筑
    if (!pTarget || pTarget->WhatAmI() != AbstractType::Building)
        return 0; // 非建筑，执行原始代码

    auto const pBuilding = static_cast<BuildingClass*>(pTarget);
    if (IsCandidateSpy(pThis))
    {
        VAMP_LOG("WhatAction building: this=%p target=%p scenario=%d",
            pThis,
            pBuilding,
            IsSpySelfStealScenario(pThis, pBuilding) ? 1 : 0);
    }

    if (!IsSpySelfStealScenario(pThis, pBuilding))
        return 0; // 非自偷场景，执行原始代码

    VAMP_LOG("WhatAction: spy self-steal on friendly Spyable building");

    // 跳过 [0xEBE]检查、[0xEC4]检查、IsAlliedWith检查、Spyable检查
    // 直接进入渗透设置：0x51EEED 设置 action=9(Capture) 并计算进入坐标
    return SkipToInfiltrationSetup;
}

// ===========================================================================
// 钩子2: FootClass::Mission_Capture 函数入口
// 地址: 0x4D4B20, 大小: 0x6
// 此处早于 Phobos 的 0x4D4B43 钩子，ECX 仍是 FootClass* this。
// 对友方间谍清空规划事件留下的 Destination，再补上 Target 使 Phobos 放行。
// 原版随后会通过 SetDestination(Target, true) 重新建立 Capture 进入状态。
// ===========================================================================
DEFINE_HOOK(0x4D4B20, FootClass_Mission_Capture_PrepareSpySelfSteal, 0x6)
{
    GET(FootClass*, pFoot, ECX);

    if (!pFoot || pFoot->WhatAmI() != AbstractType::Infantry)
        return 0;

    auto const pThis = static_cast<InfantryClass*>(pFoot);
    if (!IsCandidateSpy(pThis) || pThis->Target)
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Destination);
    if (!pBld || pBld->IsStrange() || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    VAMP_LOG("Mission_Capture prehook: reactivating friendly spy destination before Phobos");
    pThis->SetDestination(nullptr, false);
    pThis->SetTarget(pBld);
    return 0;
}

// ===========================================================================
// Temporary diagnostic: state after vanilla SetDestination(Target, true)
// Address: 0x4D4BC7, size: 0x6
// Original instruction: mov eax, [esi + 0x5A4]
// ESI = FootClass* this
// ===========================================================================
DEFINE_HOOK(0x4D4BC7, FootClass_Mission_Capture_LogSpyDestinationState, 0x6)
{
    GET(FootClass*, pFoot, ESI);

    if (!pFoot || pFoot->WhatAmI() != AbstractType::Infantry)
        return 0;

    auto const pThis = static_cast<InfantryClass*>(pFoot);
    if (!IsCandidateSpy(pThis))
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Target);
    if (!pBld || pBld->IsStrange() || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    VAMP_LOG(
        "Mission_Capture post-SetDestination: this=%p target=%p destination=%p current=%d queued=%d status=%d",
        pThis,
        pThis->Target,
        pThis->Destination,
        static_cast<int>(pThis->CurrentMission),
        static_cast<int>(pThis->QueuedMission),
        pThis->MissionStatus);

    return 0;
}

// ===========================================================================
// Allow the exact friendly spy Capture destination cell through occupancy.
// Address: 0x51BFD2, size: 0x6
// Both vanilla branches have converged here.
// EBP = InfantryClass* this, ECX = candidate CellClass*.
// Original instruction: mov al, [ecx + 0x124].
// 0x51C02D is vanilla's balanced Move::OK epilogue.
// ===========================================================================
DEFINE_HOOK(0x51BFD2, InfantryClass_IsCellOccupied_AllowSpySelfStealDestination, 0x6)
{
    enum { MoveOK = 0x51C02D };

    GET(InfantryClass*, pThis, EBP);
    GET(CellClass*, pDestCell, ECX);

    if (!IsCandidateSpy(pThis)
        || pThis->CurrentMission != Mission::Capture
        || !pDestCell)
        return 0;

    auto const pBld = reinterpret_cast<BuildingClass*(__thiscall*)(CellClass const*)>(0x47C520)(pDestCell);
    if (!pBld
        || pBld->IsStrange()
        || pThis->Target != pBld
        || pThis->Destination != pBld
        || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    VAMP_LOG("IsCellOccupied: allowing spy self-steal destination cell");
    return MoveOK;
}

// ===========================================================================
// Capture movement and building-arrival boundary
// Address: 0x519948, size: 0xA
// Original instructions obtain the current mission from ESI = InfantryClass*.
// ===========================================================================
DEFINE_HOOK(0x519948, InfantryClass_UpdatePosition_LogSpyCaptureMovement, 0xA)
{
    enum { ContinueBuildingArrival = 0x519B3E };

    GET(InfantryClass*, pThis, ESI);
    GET_STACK(CellClass*, pCell, 0x14);

    if (!IsCandidateSpy(pThis)
        || pThis->CurrentMission != Mission::Capture
        || !pCell)
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Destination);
    if (!pBld
        || pBld->IsStrange()
        || pThis->Target != pBld
        || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    auto const unitCell = pThis->GetMapCoords();
    auto const destinationCell = pBld->GetMapCoords();
    auto const pCellBld = pCell
        ? reinterpret_cast<BuildingClass*(__thiscall*)(CellClass const*)>(0x47C520)(pCell)
        : nullptr;
    VAMP_LOG(
        "UpdatePosition Capture movement: this=%p target=%p destination=%p unitCell=(%d,%d) destinationCell=(%d,%d) currentCellBuilding=%p queued=%d status=%d",
        pThis,
        pThis->Target,
        pThis->Destination,
        static_cast<int>(unitCell.X),
        static_cast<int>(unitCell.Y),
        static_cast<int>(destinationCell.X),
        static_cast<int>(destinationCell.Y),
        pCellBld,
        static_cast<int>(pThis->QueuedMission),
        pThis->MissionStatus);

    if (pCellBld != pBld)
        return 0;

    VAMP_LOG("UpdatePosition Capture arrival: entering vanilla building handling");
    R->EDI(pBld);
    return ContinueBuildingArrival;
}

// ===========================================================================
// 钩子3a: InfantryClass::UpdatePosition 工程师路径分支前置
// 地址: 0x519B58, 大小: 0x6
// 原始指令: mov eax, [esi + 0x6c0]  (加载 pThis->Owner)
//
// 到达此钩子时：
//   - ESI = pThis (InfantryClass*)
//   - EDI = pBuilding (BuildingClass*)
//   - 间谍已到达建筑旁边，通过 0x519948 或原版 CellClass::GetBuilding 解析进入
//
// 原版逻辑：加载 Owner 后，在 0x519B5E 读取 [Owner + 0xEC3]
//   (HouseClass::Side2TechInfiltrated)。若 [0xEC3]==0，跳到 0x519FF8 渗透门；
//   若 [0xEC3]!=0，落入 0x519B6C 工程师修建筑路径，永远不会触发渗透。
//   玩家房屋的 [0xEC3] 通常非零，导致间谍自偷场景下 0x519FF8 完全不可达。
//
// 我们的逻辑：如果是间谍自偷场景，直接跳到 0x51A002 渗透体（跳过 [0xEC3] 检查、
//   工程师路径、以及 0x519FF8 的 [0xEC4] 检查）。0x51A002 处的原版代码为：
//     mov eax, [esi+0x21c]  ; pThis->Type
//     mov ecx, edi           ; pBld
//     push eax
//     call 0x4571e0          ; BuildingClass::InfiltratedBy(pThis->Type)
//   ESI/EDI 在此路径中未被破坏，直接可用。
//
//   注意：不能跳到 0x519FF8（另一个 DEFINE_HOOK 地址）。Syringe 的 hook-to-hook
//   跳转不会触发目标钩子，导致 0x519FF8 钩子静默失效。必须直接跳到 0x51A002。
//
//   非自偷场景返回 0，Syringe 回放原始 mov 指令，EAX 被正确加载，
//   后续若 [0xEC3]==0 走原版到 0x519FF8，0x519FF8 钩子仍正常工作。
// ===========================================================================
DEFINE_HOOK(0x519B58, InfantryClass_UpdatePosition_SpySelfSteal_SkipEngineerPath, 0x6)
{
    enum { ContinueAfterInfiltration = 0x51A010 };

    GET(InfantryClass*, pThis, ESI);
    GET(BuildingClass*, pBuilding, EDI);

    if (!IsSpySelfStealScenario(pThis, pBuilding))
        return 0;

    // 保存上下文供 InfiltratedBy 钩子使用
    VAMP_LOG("UpdatePosition: spy self-steal, triggering infiltration (skip engineer path)");
    TriggerSpySelfStealInfiltration(pThis, pBuilding);

    return ContinueAfterInfiltration;
}

// ===========================================================================
// 钩子3b: InfantryClass::UpdatePosition 最终渗透门
// 地址: 0x519FF8, 大小: 0xA
// 原始指令:
//   0x519FF8: mov cl, [eax + 0xEC4]
//   0x519FFE: test cl, cl
//   0x51A000: je 0x51A03E  (如果 Owner->[0xEC4]==0 则跳过渗透)
//
// 到达此钩子时：
//   - ESI = pThis (InfantryClass*)
//   - EDI = pBuilding (BuildingClass*)
//   - 间谍已到达建筑旁边
//
// 原始逻辑：检查 Owner->[0xEC4]，如果为0则跳过渗透(跳到0x51A03E)
//   [0xEC4] 决定了 WhatAction 中检查 Spyable 还是 ClickRepairable
//   如果 [0xEC4]==0，即使建筑是 Spyable，渗透也不会触发
//
// 我们的逻辑：如果是间谍自偷场景，跳过 je 指令，继续执行渗透
//   注意：从 0x519B58 跳转过来时 EAX 未被加载，但自偷场景下直接返回
//   0x51A002，跳过 [eax + 0xEC4] 读取，EAX 值无关。
// ===========================================================================
DEFINE_HOOK(0x519FF8, InfantryClass_UpdatePosition_SpySelfSteal, 0xA)
{
    enum { ContinueAfterInfiltration = 0x51A010 };

    GET(InfantryClass*, pThis, ESI);
    GET(BuildingClass*, pBuilding, EDI);

    if (IsCandidateSpy(pThis))
    {
        VAMP_LOG("UpdatePosition EC4 check: this=%p building=%p scenario=%d",
            pThis,
            pBuilding,
            IsSpySelfStealScenario(pThis, pBuilding) ? 1 : 0);
    }

    if (!IsSpySelfStealScenario(pThis, pBuilding))
        return 0; // 非自偷场景，执行原始代码

    // 保存上下文供 InfiltratedBy 钩子使用
    VAMP_LOG("UpdatePosition: spy self-steal, triggering infiltration");
    TriggerSpySelfStealInfiltration(pThis, pBuilding);

    // 跳过 je 0x51A03E，继续执行：
    //   0x51A002: mov eax, [esi+0x21c]  (pThis->Type)
    //   0x51A00A: call 0x4571E0         (BuildingClass::InfiltratedBy)
    return ContinueAfterInfiltration;
}

// ===========================================================================
// 钩子4: BuildingClass::InfiltratedBy 强制自偷渗透效果
// 地址: 0x45723C, 大小: 0x6
// 原始指令: mov ecx, [ebp + 0x520]  (加载 BuildingTypeClass*)
//
// 反汇编分析发现 InfiltratedBy 内部有一个局部标志 [ESP+0x13]：
//   - 0x4571EF: 初始化为 0
//   - 0x457238: 仅当 0x65fa70 (所有权/敌对检查) 返回非零时设为 1
//   - 所有效果分支都检查此标志，为 0 时跳到 0x457590 (无效果退出)
//
// 对于己方/盟友建筑（自偷场景），0x65fa70 返回 0（非敌对），
// 标志保持 0，所有渗透效果被跳过——这就是间谍进去了但没效果的原因。
//
// 本钩子在标志设置块之后、第一个效果分支之前拦截：
//   如果是自偷场景，强制 [ESP+0x13] = 1，使所有效果分支正常执行。
//   然后清除全局上下文防止残留。
//
// 栈布局（push ecx/ebp/edi/ebx/esi 后）：
//   [ESP+0x00] = esi, [ESP+0x04] = ebx, [ESP+0x08] = edi
//   [ESP+0x0C] = ebp, [ESP+0x10] = saved ecx, [ESP+0x13] = 标志字节
//   [ESP+0x14] = ret addr, [ESP+0x18] = arg (InfantryTypeClass*)
// ===========================================================================
DEFINE_HOOK(0x45723C, BuildingClass_InfiltratedBy_ForceSelfStealFlag, 0x6)
{
    GET(BuildingClass*, pBuilding, EBP);

    if (!g_SpySelfSteal_Infantry || !g_SpySelfSteal_Building)
        return 0;

    // 强制渗透标志为 1，绕过友方/盟友检查
    R->Stack8(0x13, static_cast<BYTE>(1));

    VAMP_LOG(
        "InfiltratedBy: forcing infiltration flag for spy self-steal, ebpBuilding=%p savedBuilding=%p",
        pBuilding,
        g_SpySelfSteal_Building);

    // 清除上下文防止残留（单线程，同步调用链已完成传递）
    g_SpySelfSteal_Infantry = nullptr;
    g_SpySelfSteal_Building = nullptr;

    return 0;
}

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
        gVampireModule = hModule;
#endif
        VAMP_LOG("DllMain - DLL_PROCESS_ATTACH, hModule=0x%p", hModule);
    }
    return TRUE;
}
