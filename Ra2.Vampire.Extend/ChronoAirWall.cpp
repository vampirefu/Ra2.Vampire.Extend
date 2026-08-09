// ===========================================================================
// 超时空步兵下车空气墙修复 - 实现与钩子
// ===========================================================================

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

// YRpp headers use 'byte' (lowercase) which is not a standard C++ type
using byte = unsigned char;

#include <Syringe.h>
// Include class headers first so AbstractTypeClass is defined before Cast.h
#include <InfantryClass.h>
#include <BuildingClass.h>
#include <CellClass.h>
#include <UnitClass.h>
#include <MapClass.h>
#include <HouseClass.h>
#include <FootClass.h>
#include <LocomotionClass.h>
#include <Unsorted.h>
#include <Helpers/Macro.h>
#include <Helpers/Cast.h>

#include "VampireLog.h"
#include "VampireConfig.h"
#include "ChronoAirWall.h"

namespace ChronoAirWall
{
    // 判定兵种是否为超时空步兵（静态规则 CLSID 匹配，兼容所有 Teleport 派生）
    static bool IsChronoInfantryType(TechnoTypeClass const* pType)
    {
        if (!pType)
            return false;
        return IsEqualGUID(pType->Locomotor, LocomotionClass::CLSIDs::Teleport) != FALSE;
    }

    static bool IsChronoInfantry(FootClass const* pFoot)
    {
        if (!pFoot || pFoot->WhatAmI() != AbstractType::Infantry)
            return false;
        auto const pInf = static_cast<InfantryClass const*>(pFoot);
        return IsChronoInfantryType(pInf->Type);
    }

    // 以 pOriginCell 为原点扫描 8 方向邻格，返回首个可站立单元格与坐标。
    // 通行判定复用引擎原生 ObjectClass::IsCellOccupied（与 Phobos EjectRandomly
    // 完全一致：OK / MovingBlock 视为可用），自动过滤水域/悬崖/建筑/单位占用。
    static CellClass* FindClearNeighborCell(FootClass* pPassenger, CellClass const* pOriginCell,
                                            CoordStruct& outCoord)
    {
        if (!pPassenger || !pOriginCell)
            return nullptr;

        auto const origin = pOriginCell->MapCoords;
        auto const baseZ = pOriginCell->GetCoordsWithBridge().Z;

        for (int dir = 0; dir < 8; ++dir)
        {
            CellStruct cand
            {
                static_cast<short>(origin.X + Unsorted::AdjacentCell[dir].X),
                static_cast<short>(origin.Y + Unsorted::AdjacentCell[dir].Y)
            };

            auto const pCell = MapClass::Instance.TryGetCellAt(cand);
            if (!pCell)
                continue;

            auto const move = pPassenger->IsCellOccupied(pCell, FacingType::None, -1, nullptr, true);
            if (move != Move::OK && move != Move::MovingBlock)
                continue;

            CoordStruct coord = CellClass::Cell2Coord(pCell->MapCoords, baseZ);
            coord = pCell->FindInfantrySubposition(coord, false, false, false);
            if (coord == CoordStruct::Empty)
                continue;

            outCoord = coord;
            return pCell;
        }

        return nullptr;
    }

    // 将超时空乘客安全重定位至邻格。
    // 复用 Phobos TechnoExt::EjectSurvivor 的非伞降重定位序列：
    //   RemovePassenger -> Unlimbo(邻格) -> 清理 Transporter -> LastMapCoords
    //   -> Scatter -> QueueMission -> 重置进入旗标。
    // Unlimbo 会正确建立新单元格占位，从源头避免幽灵空气墙。
    static bool DismountChronoPassengerToNeighbor(UnitClass* pVehicle)
    {
        if (!pVehicle)
            return false;

        auto const pPassenger = pVehicle->Passengers.GetFirstPassenger();
        if (!pPassenger || !IsChronoInfantry(pPassenger))
            return false;

        auto const pOriginCell = pVehicle->GetCell();
        if (!pOriginCell)
            return false;

        CoordStruct coord {};
        auto const pDestCell = FindClearNeighborCell(pPassenger, pOriginCell, coord);
        if (!pDestCell)
        {
            VAMP_LOG("ChronoAirWall: no clear neighbor cell, keep passenger in vehicle this=%p", pVehicle);
            return false;
        }

        // 从载具移除
        pVehicle->Passengers.RemovePassenger(pPassenger);

        // 非伞降重定位（地面）：对齐桥面 Z，ScenarioInit 守卫与 Phobos 一致
        pPassenger->OnBridge = pDestCell->ContainsBridge();
        coord.Z = pDestCell->GetCoordsWithBridge().Z;

        ++Unsorted::ScenarioInit;
        bool const ok = pPassenger->Unlimbo(coord, DirType::North);
        --Unsorted::ScenarioInit;

        if (!ok)
        {
            VAMP_LOG("ChronoAirWall: Unlimbo failed this=%p", pPassenger);
            return false;
        }

        // 清理 OpenTopped 运输状态
        if (auto const pTransporter = pPassenger->Transporter)
        {
            if (pTransporter->GetTechnoType()->OpenTopped)
                pTransporter->ExitedOpenTopped(pPassenger);
            pPassenger->Transporter = nullptr;
        }

        pPassenger->LastMapCoords = pDestCell->MapCoords;
        pPassenger->Scatter(CoordStruct::Empty, true, false);

        auto const pOwner = pPassenger->Owner;
        pPassenger->QueueMission(
            pOwner && pOwner->IsControlledByHuman() ? Mission::Guard : Mission::Hunt, 0);

        pPassenger->ShouldEnterOccupiable = false;
        pPassenger->ShouldGarrisonStructure = false;

        VAMP_LOG("ChronoAirWall: dismounted chrono infantry %p to cell (%d,%d) from vehicle %p",
            pPassenger,
            static_cast<int>(pDestCell->MapCoords.X),
            static_cast<int>(pDestCell->MapCoords.Y),
            pVehicle);
        return true;
    }
}

// ---------------------------------------------------------------------------
// 入口1：D 键手动卸载乘客
// 地址 0x73D63B（UnitClass::Mi_Unload 入口，Phobos 已验证的钩子点），大小 0x6
// ESI = UnitClass* this
//
// 仅当首位乘客为超时空步兵时介入；连续卸载队列前方的所有超时空步兵，
// 遇非超时空乘客交还原版流程。四周全堵的超时空乘客保留在车内（跳过本帧
// 卸载）。非超时空场景一律返回 0，原版 / Phobos 既有行为完全不受影响。
// ---------------------------------------------------------------------------
DEFINE_HOOK(0x73D63B, UnitClass_Mi_Unload_ChronoDismount, 0x6)
{
    enum { SkipPassengers = 0x73DCD3 };

    if (!VampireConfig::ChronoAirWallFixEnabled)
        return 0;

    GET(UnitClass*, pThis, ESI);
    if (!pThis || pThis->Passengers.NumPassengers <= 0)
        return 0;

    auto const pFirst = pThis->Passengers.GetFirstPassenger();
    if (!pFirst || !ChronoAirWall::IsChronoInfantry(pFirst))
        return 0;

    // 连续卸载队列前方的超时空步兵；遇非超时空乘客或无邻格时停止
    bool dismountedAny = false;
    while (auto const p = pThis->Passengers.GetFirstPassenger())
    {
        if (!ChronoAirWall::IsChronoInfantry(p))
            break;
        if (!ChronoAirWall::DismountChronoPassengerToNeighbor(pThis))
            break; // 四周全堵，保留在车内
        dismountedAny = true;
    }

    if (!dismountedAny)
        return 0; // 本帧未卸载，交原版处理（含原版同格放置行为）

    // 剩余首位仍为超时空（四周全堵）：跳过本帧卸载，步兵留在车内
    auto const pRemaining = pThis->Passengers.GetFirstPassenger();
    if (pRemaining && ChronoAirWall::IsChronoInfantry(pRemaining))
    {
        VAMP_LOG("ChronoAirWall: chrono passenger blocked, keep in vehicle %p", pThis);
        return SkipPassengers;
    }

    // 已卸载超时空乘客，剩余为非超时空或空：交原版处理剩余乘客
    return 0;
}
