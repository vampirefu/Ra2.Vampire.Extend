# Spy Self-Steal Final Entry Boundary Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distinguish the `0x519AFA` path-head early-return branch from the `0x519B1B` current-cell building lookup in one AGWar reproduction without changing gameplay state.

**Architecture:** Add two temporary, strictly filtered observers inside vanilla `InfantryClass::UpdatePosition`. Both observers require the exact friendly self-steal Capture scenario, log only the data already present at their boundaries, and return `0` so Syringe replays the complete original instruction; the current-cell observer uses the validated direct `__thiscall` to `0x47C520` only for diagnostic comparison.

**Tech Stack:** C++20, YRPP/Syringe hooks, MSVC x86 `__thiscall`, PowerShell source checks, Dumpbin object-code inspection, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Specify both read-only observers

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require the path-head observer**

Add checks requiring:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519AFA,\s*InfantryClass_UpdatePosition_LogSpyPathHeadReached,\s*0x6\)' `
    -Message 'Missing read-only spy path-head observer at 0x519AFA.'

$pathHeadHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519AFA,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value
```

Add the complete body checks:

```powershell
Assert-Contains -Text $pathHeadHook -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' -Message 'The path-head observer must read InfantryClass this from ESI.'
Assert-Contains -Text $pathHeadHook -Pattern '!IsCandidateSpy\(pThis\)[\s\S]*pThis->CurrentMission\s*!=\s*Mission::Capture' -Message 'The path-head observer must require a strict Capture spy.'
Assert-Contains -Text $pathHeadHook -Pattern 'specific_cast<BuildingClass\*>\(pThis->Destination\)' -Message 'The path-head observer must resolve Destination as a building.'
Assert-Contains -Text $pathHeadHook -Pattern 'pThis->Target\s*!=\s*pBld[\s\S]*!IsSpySelfStealScenario\(pThis,\s*pBld\)' -Message 'The path-head observer must require exact friendly Spyable Target/Destination identity.'
Assert-Contains -Text $pathHeadHook -Pattern 'unitCell\s*=\s*pThis->GetMapCoords\(\);[\s\S]*destinationCell\s*=\s*pBld->GetMapCoords\(\);' -Message 'The path-head observer must read unit and destination cells.'
Assert-Contains -Text $pathHeadHook -Pattern 'UpdatePosition path-head reached: this=%p target=%p destination=%p unitCell=\(%d,%d\) destinationCell=\(%d,%d\)' -Message 'The path-head observer must emit the exact diagnostic format.'
Assert-Contains -Text $pathHeadHook -Pattern 'return\s+0;' -Message 'The path-head observer must continue vanilla control.'
```

- [x] **Step 2: Require the current-cell building observer**

Add checks requiring:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519B1B,\s*InfantryClass_UpdatePosition_LogSpyCurrentCellBuilding,\s*0x5\)' `
    -Message 'Missing read-only current-cell building observer at 0x519B1B.'

$currentCellHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519B1B,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value
```

Add the complete body checks:

```powershell
Assert-Contains -Text $currentCellHook -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' -Message 'The current-cell observer must read InfantryClass this from ESI.'
Assert-Contains -Text $currentCellHook -Pattern 'GET\(CellClass\*,\s*pCell,\s*ECX\);' -Message 'The current-cell observer must read current CellClass from ECX.'
Assert-Contains -Text $currentCellHook -Pattern '!IsCandidateSpy\(pThis\)[\s\S]*pThis->CurrentMission\s*!=\s*Mission::Capture[\s\S]*!pCell' -Message 'The current-cell observer must require a strict Capture spy and current cell.'
Assert-Contains -Text $currentCellHook -Pattern 'specific_cast<BuildingClass\*>\(pThis->Destination\)' -Message 'The current-cell observer must resolve Destination as a building.'
Assert-Contains -Text $currentCellHook -Pattern 'pThis->Target\s*!=\s*pBld[\s\S]*!IsSpySelfStealScenario\(pThis,\s*pBld\)' -Message 'The current-cell observer must require exact friendly Spyable Target/Destination identity.'
Assert-Contains -Text $currentCellHook -Pattern 'reinterpret_cast<BuildingClass\*\(__thiscall\*\)\(CellClass const\*\)>\(0x47C520\)\(pCell\)' -Message 'The current-cell observer must call vanilla GetBuilding directly.'
Assert-Contains -Text $currentCellHook -Pattern 'pCell->MapCoords\.X[\s\S]*pCell->MapCoords\.Y' -Message 'The current-cell observer must log current cell coordinates.'
Assert-Contains -Text $currentCellHook -Pattern 'UpdatePosition current-cell building lookup: this=%p cell=\(%d,%d\) cellBuilding=%p target=%p destination=%p' -Message 'The current-cell observer must emit the exact diagnostic format.'
Assert-Contains -Text $currentCellHook -Pattern 'return\s+0;' -Message 'The current-cell observer must continue vanilla control.'
```

For both hook bodies, reject these patterns:

```powershell
foreach ($hook in @($pathHeadHook, $currentCellHook)) {
    foreach ($pattern in @(
        'SetDestination\(', 'SetTarget\(', 'QueueMission\(', 'NextMission\(',
        'ClearNavigationList\(', 'ApproachTarget\(', 'StopMoving\(',
        'SetLocation\(', 'SetPosition\(', 'SetMapCoords\(', 'Limbo\(',
        'Unlimbo\(', 'Mark\(', 'Unmark\(', 'Locomotor->',
        'pThis->(?:CurrentMission|QueuedMission|MissionStatus|Target|Destination)\s*=(?!=)'
    )) {
        if ($hook -match $pattern) {
            throw "Final-entry observers must remain read-only; found: $pattern"
        }
    }
}
```

- [x] **Step 3: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `1` with `Missing read-only spy path-head observer at 0x519AFA.`

### Task 2: Add the two minimal observers

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Add the `0x519AFA` observer**

Insert after the existing `0x519948` movement observer:

```cpp
// ===========================================================================
// Temporary diagnostic: Capture path-head reached before building lookup.
// Address: 0x519AFA, size: 0x6
// ESI = InfantryClass* this.
// Original instruction: mov eax, [esi + 0x5A4].
// ===========================================================================
DEFINE_HOOK(0x519AFA, InfantryClass_UpdatePosition_LogSpyPathHeadReached, 0x6)
{
    GET(InfantryClass*, pThis, ESI);

    if (!IsCandidateSpy(pThis) || pThis->CurrentMission != Mission::Capture)
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Destination);
    if (!pBld
        || pBld->IsStrange()
        || pThis->Target != pBld
        || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    auto const unitCell = pThis->GetMapCoords();
    auto const destinationCell = pBld->GetMapCoords();
    VAMP_LOG(
        "UpdatePosition path-head reached: this=%p target=%p destination=%p unitCell=(%d,%d) destinationCell=(%d,%d)",
        pThis,
        pThis->Target,
        pThis->Destination,
        static_cast<int>(unitCell.X),
        static_cast<int>(unitCell.Y),
        static_cast<int>(destinationCell.X),
        static_cast<int>(destinationCell.Y));

    return 0;
}
```

- [x] **Step 2: Add the `0x519B1B` observer**

Insert immediately after the path-head observer:

```cpp
// ===========================================================================
// Temporary diagnostic: building resolved from the infantry's current cell.
// Address: 0x519B1B, size: 0x5
// ESI = InfantryClass* this, ECX = current CellClass*.
// Original instruction: call 0x47C520.
// ===========================================================================
DEFINE_HOOK(0x519B1B, InfantryClass_UpdatePosition_LogSpyCurrentCellBuilding, 0x5)
{
    GET(InfantryClass*, pThis, ESI);
    GET(CellClass*, pCell, ECX);

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

    auto const pCellBld = reinterpret_cast<BuildingClass*(__thiscall*)(CellClass const*)>(0x47C520)(pCell);
    VAMP_LOG(
        "UpdatePosition current-cell building lookup: this=%p cell=(%d,%d) cellBuilding=%p target=%p destination=%p",
        pThis,
        static_cast<int>(pCell->MapCoords.X),
        static_cast<int>(pCell->MapCoords.Y),
        pCellBld,
        pThis->Target,
        pThis->Destination);

    return 0;
}
```

Do not change existing gameplay hooks or temporary diagnostics.

- [x] **Step 3: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `0` and `Spy self-steal source checks passed.`

### Task 3: Verify addresses and build artifacts

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Inspect: `Ra2.Vampire.Extend/Debug/dllmain.obj`

- [x] **Step 1: Reconfirm vanilla instruction boundaries**

Run Dumpbin on `gamemd.exe` ranges `0x519AF4-0x519B10` and `0x519B17-0x519B24`. Require the complete six-byte `mov` at `0x519AFA` and complete five-byte `call 0x47C520` at `0x519B1B`.

- [x] **Step 2: Rebuild Release and Debug Win32**

Run MSBuild `/t:Rebuild` for `Release|Win32` and `Debug|Win32` using:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
```

Repeat with `/p:Configuration=Debug`. Both commands must exit `0` with no compiler or linker errors.

- [x] **Step 3: Inspect Debug observer code generation**

Use Dumpbin `/disasm:nobytes` on `Ra2.Vampire.Extend\Debug\dllmain.obj`. Require both observer symbols. Within `InfantryClass_UpdatePosition_LogSpyCurrentCellBuilding`, require `mov eax,47C520h`, a load of captured `pCell` into `ECX`, and `call eax`; reject `?GetBuilding@CellClass`.

### Task 4: Guard and deploy Debug

**Files:**
- Source: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Abort if AGWar is running**

Resolve the game directory and query `Win32_Process.ExecutablePath`. Abort before file changes if any process path starts with the resolved directory.

- [x] **Step 2: Back up and deploy**

Back up the current DLL and log using suffix `.bak-finalentrydiag-yyyyMMdd-HHmmss`, deploy the Debug DLL, and require built/deployed SHA256 equality.

### Task 5: Final automated verification and runtime classification

- [x] **Step 1: Verify source, Debug code, deployment, and Phobos state**

Re-run the full source check, focused Debug object-code assertions, Debug/deployed SHA256 equality, and both Phobos tracked/staged `git diff --quiet` checks. All must pass.

- [ ] **Step 2: Reproduce and classify**

Queue engineer and spy through waypoint A to the damaged friendly `Spyable` barracks, then classify the newest sequence:

- path-head log only: early re-approach branch;
- current-cell log with null/different building: cell resolution mismatch;
- current-cell log with exact building but no EC4: remaining identity/owner branch;
- neither log: locomotor stops earlier.

Do not create a worktree, modify Phobos, remove existing diagnostics, or commit.
