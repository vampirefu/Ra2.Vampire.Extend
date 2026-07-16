# Spy Self-Steal Safe Occupancy Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the split-instruction crash by moving the strict spy self-steal occupancy exception from `0x51BFA8/0x7` to the complete instruction boundary at `0x51BFD2/0x6`.

**Architecture:** Preserve the existing strict, read-only occupancy filter and vanilla `Move::OK` epilogue. Change only the hook address and saved-byte length so the original-return path replays the complete six-byte `mov al,[ecx+0x124]` after the vanilla branches converge; explicitly forbid both the Phobos-owned `0x51BFA2` address and the crash-prone `0x51BFA8` address.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Add a regression check for the safe instruction boundary

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require `0x51BFD2/0x6` and reject the old address**

Replace the current occupancy-hook assertion and extraction with:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x51BFD2,\s*InfantryClass_IsCellOccupied_AllowSpySelfStealDestination,\s*0x6\)' `
    -Message 'Missing safe IsCellOccupied spy self-steal destination hook at 0x51BFD2.'

Assert-Contains `
    -Text $source `
    -Pattern '#include\s*<CellClass\.h>' `
    -Message 'The IsCellOccupied hook requires CellClass.h.'

$occupancyHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x51BFD2,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value
```

Replace the single `0x51BFA2` rejection with:

```powershell
foreach ($address in @('0x51BFA2', '0x51BFA8')) {
    if ($source -match "DEFINE_HOOK\($address,") {
        throw "The local plugin must not hook unsafe or Phobos-owned IsCellOccupied address: $address"
    }
}
```

Keep all existing register, strict-filter, `MoveOK`, logging, fall-through, and mutation checks unchanged so they apply to the new `$occupancyHook` block.

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `1` with `Missing safe IsCellOccupied spy self-steal destination hook at 0x51BFD2.` The failure must occur before the old-address rejection and must be caused by the still-present `0x51BFA8/0x7` production hook.

### Task 2: Move the hook to the complete instruction boundary

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Change only the hook boundary and explanatory comment**

Replace the occupancy-hook header and declaration with:

```cpp
// ===========================================================================
// Allow the exact friendly spy Capture destination cell through occupancy.
// Address: 0x51BFD2, size: 0x6
// Both vanilla branches have converged here.
// EBP = InfantryClass* this, ECX = candidate CellClass*.
// Original instruction: mov al, [ecx + 0x124].
// 0x51C02D is vanilla's balanced Move::OK epilogue.
// ===========================================================================
DEFINE_HOOK(0x51BFD2, InfantryClass_IsCellOccupied_AllowSpySelfStealDestination, 0x6)
```

Leave the entire function body unchanged:

```cpp
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

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `0` and `Spy self-steal source checks passed.`

- [x] **Step 3: Verify the on-disk game instruction boundary and address ownership**

Run:

```powershell
$dumpbin = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x86\dumpbin.exe'
& $dumpbin /disasm:bytes /range:0x51BFC6,0x51BFDF 'C:\Users\Vampire\Desktop\AGWar1.3.1\gamemd.exe'
rg -n -i '0x0*51BFD2|51BFD2' 'E:\WorkSpace\cncnet\phobos-release\src' 'E:\WorkSpace\cncnet\phobos-release\.agents'
```

Expected: `0x51BFD2` starts `8A 81 24 01 00 00` (`mov al,[ecx+0x124]`), the next instruction starts at `0x51BFD8`, and the Phobos/Ares search has no match.

### Task 3: Rebuild both Win32 configurations

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Artifacts: `bin/Release/Ra2.Vampire.Extend.dll`, `bin/Debug/Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Release Win32**

Run:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0`; the existing YRPP `CellClass::GetBuilding` C4731 thunk warning may remain, but there must be no compiler or linker errors.

- [x] **Step 2: Rebuild Debug Win32**

Run the same command with `/p:Configuration=Debug`.

Expected: exit code `0`; the Debug DLL and PDB are regenerated with no compiler or linker errors.

### Task 4: Guard, back up, and deploy the Debug DLL

**Files:**
- Source: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Abort if AGWar is running**

Resolve the game directory and query `Win32_Process.ExecutablePath`. If any process path begins with the resolved AGWar directory, throw `AGWar 1.3.1 is running; deployment aborted.` before copying or replacing files.

- [x] **Step 2: Back up and deploy**

Back up the existing DLL and log using suffix `.bak-safeoccupancy-yyyyMMdd-HHmmss`, copy the Debug DLL with `-Force`, and compare SHA256 hashes. Abort if the source and deployed hashes differ.

### Task 5: Fresh automated verification and runtime handoff

- [x] **Step 1: Verify source, deployment, and Phobos state**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
$debugHash = (Get-FileHash -LiteralPath 'bin\Debug\Ra2.Vampire.Extend.dll' -Algorithm SHA256).Hash
$deployedHash = (Get-FileHash -LiteralPath 'C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll' -Algorithm SHA256).Hash
if ($debugHash -ne $deployedHash) { throw 'Debug/deployed hash mismatch.' }
git -C 'E:\WorkSpace\cncnet\phobos-release' diff --quiet
if ($LASTEXITCODE -ne 0) { throw 'Phobos tracked working-tree files changed.' }
git -C 'E:\WorkSpace\cncnet\phobos-release' diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw 'Phobos staged files changed.' }
```

Expected: source check passes, hashes match, and both Phobos diff commands return `0`.

- [ ] **Step 2: Reproduce the same AGWar route**

Select engineer and spy, queue waypoint A, then queue the damaged friendly `Spyable` barracks. Success requires all of the following:

1. no `C0000005` or new crash snapshot;
2. `IsCellOccupied: allowing spy self-steal destination cell` appears;
3. `UpdatePosition EC4 check` appears;
4. `UpdatePosition: spy self-steal, triggering infiltration` appears;
5. the engineer and spy enter, the infiltration effect executes, and the game remains stable.

Do not remove the temporary `0x4D4BC7` and `0x519948` diagnostics until this runtime validation succeeds. Do not create a worktree, modify Phobos, or commit.
