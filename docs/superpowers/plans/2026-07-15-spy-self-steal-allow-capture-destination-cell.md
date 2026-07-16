# Spy Self-Steal Allow Capture Destination Cell Implementation Plan

> **For agentic workers:** Execute each checkbox in order. Preserve the temporary diagnostics through the first successful runtime validation.

**Goal:** Allow only a strict friendly self-steal spy in `Mission::Capture` to enter the foundation cell of its exact `Target`/`Destination` building so vanilla `UpdatePosition` can trigger infiltration.

**Architecture:** Add a non-overlapping hook at `0x51BFA8`, immediately after Phobos's `0x51BFA2` range. Read `InfantryClass*` from `EBP` and candidate `CellClass*` from `ECX`; return vanilla's balanced `Move::OK` epilogue at `0x51C02D` only for the exact friendly `Spyable` capture destination. Return `0` for every other case so the original occupancy logic is replayed. Do not mutate missions, paths, positions, targets, destinations, locomotor state, or occupancy state.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Specify the occupancy exception

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require the exact hook, registers, and strict filter**

Add source checks that require:

- `#include <CellClass.h>`;
- `DEFINE_HOOK(0x51BFA8, InfantryClass_IsCellOccupied_AllowSpySelfStealDestination, 0x7)`;
- `MoveOK = 0x51C02D`;
- `GET(InfantryClass*, pThis, EBP)` and `GET(CellClass*, pDestCell, ECX)`;
- `IsCandidateSpy(pThis)` and `CurrentMission == Mission::Capture`;
- `pDestCell->GetBuilding()`;
- rejection of null and `IsStrange()` buildings;
- exact `pThis->Target == pBld` and `pThis->Destination == pBld` identity checks;
- `IsSpySelfStealScenario(pThis, pBld)`;
- a filtered diagnostic log and `return MoveOK`;
- normal `return 0` fall-through for all other cases.

Reject any local hook at `0x51BFA2`. Within the new hook, reject mission/path/position/target/destination/locomotor/occupancy mutations, including setters, queue operations, navigation clearing, movement forcing, direct state assignments, and marking/unmarking calls.

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: failure with `Missing IsCellOccupied spy self-steal destination hook at 0x51BFA8.` The failure must be caused by the absent production hook, not by a test syntax error.

### Task 2: Add the minimal occupancy exception

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Add `CellClass` and the `0x51BFA8` hook**

Add `#include <CellClass.h>` if it is not already present. Insert the hook before the existing `0x519948` diagnostic hook:

```cpp
DEFINE_HOOK(0x51BFA8, InfantryClass_IsCellOccupied_AllowSpySelfStealDestination, 0x7)
{
    enum { MoveOK = 0x51C02D };

    GET(InfantryClass*, pThis, EBP);
    GET(CellClass*, pDestCell, ECX);

    if (!IsCandidateSpy(pThis)
        || pThis->CurrentMission != Mission::Capture
        || !pDestCell)
        return 0;

    auto const pBld = pDestCell->GetBuilding();
    if (!pBld
        || pBld->IsStrange()
        || pThis->Target != pBld
        || pThis->Destination != pBld
        || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    VAMP_LOG("IsCellOccupied: allowing spy self-steal destination cell");
    return MoveOK;
}
```

Do not change the existing `0x51EE4E`, `0x4D4B20`, `0x4D4BC7`, `0x519948`, or `0x519FF8` hooks.

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 3: Inspect hook ownership and focused diff**

Run:

```powershell
rg -n -A 45 'DEFINE_HOOK\(0x51BFA8' 'Ra2.Vampire.Extend\dllmain.cpp'
rg -n -i '0x0*51BFA8|51BFA8' 'E:\WorkSpace\cncnet\phobos-release\src' 'E:\WorkSpace\cncnet\phobos-release\.agents'
git diff -- 'Ra2.Vampire.Extend/dllmain.cpp' 'tests/check-spy-self-steal.ps1'
```

Expected: the new hook is narrowly filtered and read-only; the checked Phobos/Ares sources have no `0x51BFA8` owner.

### Task 3: Build Release and Debug

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Artifacts: `bin/Release/Ra2.Vampire.Extend.dll`, `bin/Debug/Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Release Win32**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0`, no compiler errors.

- [x] **Step 2: Rebuild Debug Win32**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Debug /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0`, no compiler errors.

### Task 4: Guard, back up, and deploy Debug

**Files:**
- Source: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Abort if a process is running from the game directory**

Resolve the game directory and inspect `Win32_Process.ExecutablePath`. If any process path starts with the resolved AGWar directory, stop deployment without modifying files.

- [x] **Step 2: Back up and deploy**

Back up the existing DLL and log with a `yyyyMMdd-HHmmss` timestamp and an `occupancy` label, copy the Debug DLL with `-Force`, and verify source/deployed SHA256 equality.

### Task 5: Final automated verification and runtime handoff

- [x] **Step 1: Run fresh automated verification**

Run the full source check again, verify Debug/deployed SHA256 equality, and verify both Phobos tracked and staged diffs are empty:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
git -C 'E:\WorkSpace\cncnet\phobos-release' diff --quiet
git -C 'E:\WorkSpace\cncnet\phobos-release' diff --cached --quiet
```

Do not create a worktree or commit.

- [ ] **Step 2: Reproduce the exact route in AGWar**

Select engineer and spy, queue waypoint A, then queue the damaged friendly `Spyable` barracks. Expected log sequence:

1. `Mission_Capture post-SetDestination`;
2. `IsCellOccupied: allowing spy self-steal destination cell`;
3. `UpdatePosition EC4 check`;
4. `UpdatePosition: spy self-steal, triggering infiltration`.

The engineer and spy must enter, the self-steal effect must execute, and the game must remain stable. Keep `0x4D4BC7` and `0x519948` until this first runtime validation succeeds.
