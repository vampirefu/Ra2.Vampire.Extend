# Spy Self-Steal Direct GetBuilding Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the Debug-only null-call crash by invoking vanilla `CellClass::GetBuilding` at `0x47C520` directly with the captured candidate cell in `ECX`.

**Architecture:** Keep the safe `0x51BFD2/0x6` occupancy hook and every strict filter unchanged. Replace only the YRPP `pDestCell->GetBuilding()` thunk call with the fixed-address `__thiscall` pattern already used by Phobos, then inspect Debug object code to prove the generated hook calls `0x47C520` directly and does not reference the broken YRPP thunk symbol.

**Tech Stack:** C++20, MSVC x86 `__thiscall`, YRPP/Syringe hooks, PowerShell source checks, Dumpbin object-code inspection, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Specify the direct vanilla call

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require the direct `__thiscall` and forbid the YRPP thunk**

Add these checks after `$occupancyHook` is extracted and before the existing building-filter assertions:

```powershell
Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'reinterpret_cast<BuildingClass\*\(__thiscall\*\)\(CellClass const\*\)>\(0x47C520\)\(pDestCell\)' `
    -Message 'The Debug-safe occupancy hook must call vanilla CellClass::GetBuilding at 0x47C520 directly.'

if ($occupancyHook -match 'pDestCell->GetBuilding\(\)') {
    throw 'The occupancy hook must not call the broken Debug YRPP CellClass::GetBuilding thunk.'
}
```

Do not weaken the existing requirements for `0x51BFD2/0x6`, `EBP`/`ECX`, exact Target/Destination identity, `IsSpySelfStealScenario`, `MoveOK`, normal fall-through, or read-only behavior.

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `1` with `The Debug-safe occupancy hook must call vanilla CellClass::GetBuilding at 0x47C520 directly.` The failure must be caused by the current `pDestCell->GetBuilding()` production line.

### Task 2: Bypass only the broken Debug thunk

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Replace the single building lookup line**

Replace:

```cpp
auto const pBld = pDestCell->GetBuilding();
```

with:

```cpp
auto const pBld = reinterpret_cast<BuildingClass*(__thiscall*)(CellClass const*)>(0x47C520)(pDestCell);
```

Do not change the hook address, saved-byte length, strict conditions, log message, return addresses, or any other hook.

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: exit code `0` and `Spy self-steal source checks passed.`

### Task 3: Rebuild and prove Debug code generation

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Inspect: `Ra2.Vampire.Extend/Debug/dllmain.obj`
- Artifacts: `bin/Release/Ra2.Vampire.Extend.dll`, `bin/Debug/Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Release Win32**

Run:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0` and no compiler or linker errors.

- [x] **Step 2: Rebuild Debug Win32**

Run the same command with `/p:Configuration=Debug`.

Expected: exit code `0` and no compiler or linker errors. The previous C4731 warning for `CellClass::GetBuilding` should disappear because the broken thunk is no longer instantiated.

- [x] **Step 3: Inspect the focused Debug hook machine code**

Run:

```powershell
$dumpbin = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x86\dumpbin.exe'
$disasm = (& $dumpbin /disasm:nobytes 'Ra2.Vampire.Extend\Debug\dllmain.obj') -join "`n"
$hookCode = [regex]::Match(
    $disasm,
    '(?ms)^_InfantryClass_IsCellOccupied_AllowSpySelfStealDestination:.*?(?=^_InfantryClass_UpdatePosition_LogSpyCaptureMovement:)'
).Value
if (-not $hookCode) { throw 'Debug occupancy hook disassembly not found.' }
if ($hookCode -match '\?GetBuilding@CellClass') { throw 'Debug hook still calls the YRPP GetBuilding thunk.' }
if ($hookCode -notmatch 'mov\s+eax,47C520h[\s\S]*call\s+eax') { throw 'Debug hook does not call vanilla GetBuilding address 0x47C520 directly.' }
$hookCode
```

Expected: the hook contains a load of captured `pDestCell` into `ECX`, followed by `mov eax,47C520h` and `call eax`; it contains no `?GetBuilding@CellClass` reference.

### Task 4: Guard, back up, and deploy Debug

**Files:**
- Source: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Abort if an AGWar process is running**

Resolve the game directory and query `Win32_Process.ExecutablePath`. Abort before file changes if any executable path starts with the resolved AGWar directory.

- [x] **Step 2: Back up and deploy**

Back up the existing DLL and log with suffix `.bak-directgetbuilding-yyyyMMdd-HHmmss`, deploy the Debug DLL with `-Force`, and require built/deployed SHA256 equality.

### Task 5: Fresh automated verification and runtime handoff

- [x] **Step 1: Verify source, code generation, deployment, and Phobos state**

Re-run the full PowerShell source check and focused Debug object-code assertions. Verify Debug/deployed SHA256 equality. Run both `git -C E:\WorkSpace\cncnet\phobos-release diff --quiet` and `git -C E:\WorkSpace\cncnet\phobos-release diff --cached --quiet`; both must return `0`.

- [ ] **Step 2: Reproduce the same route**

Select engineer and spy, queue waypoint A, then queue the damaged friendly `Spyable` barracks. Success requires:

1. no new `C0000005` snapshot;
2. `IsCellOccupied: allowing spy self-steal destination cell`;
3. `UpdatePosition EC4 check`;
4. `UpdatePosition: spy self-steal, triggering infiltration`;
5. both units enter, the infiltration effect executes, and the game stays stable.

Keep temporary `0x4D4BC7` and `0x519948` diagnostics until runtime succeeds. Do not create a worktree, modify Phobos, or commit.
