# Spy Self-Steal Delayed Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delay the friendly spy building target assignment until vanilla `Mission_Capture` has activated the final destination, allowing the spy to continue beyond waypoint A.

**Architecture:** Keep the existing mouse-action and infiltration hooks. Let vanilla execute `SetDestination` while `Target` is null, then assign the friendly Spyable building in a new hook at `0x4D4BC7` before vanilla checks whether the target is still null.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1.

---

### Task 1: Add the delayed-target regression constraint

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Replace the early-target assertions**

Require the source to contain:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x4D4BC7,\s*FootClass_Mission_Capture_SetSpyTargetAfterDestination,\s*0x6\)' `
    -Message 'Missing delayed spy target hook immediately after vanilla SetDestination handling.'

Assert-Contains `
    -Text $source `
    -Pattern 'Mission_Capture: spy self-steal, deferring target until vanilla SetDestination' `
    -Message 'Mission_Capture entry must defer Target so vanilla can activate the queued building destination.'

Assert-Contains `
    -Text $source `
    -Pattern 'Mission_Capture: spy self-steal, setting target after vanilla SetDestination' `
    -Message 'Delayed hook must document the post-SetDestination Target assignment.'
```

Add a scoped assertion proving `SetTarget` appears only in the delayed hook:

```powershell
$entryHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x4D4B43,[\s\S]*?(?=^DEFINE_HOOK\(|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value
if ($entryHook -match 'SetTarget\(') {
    throw 'Mission_Capture entry must not set Target before vanilla SetDestination.'
}
```

- [x] **Step 2: Run the check and verify RED**

Run:

```powershell
& 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\tests\check-spy-self-steal.ps1'
```

Expected: failure reporting the missing `0x4D4BC7` hook or the forbidden early `SetTarget`.

### Task 2: Move Target assignment behind vanilla SetDestination

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Remove the entry-hook mutation**

Replace the first-phase mutation with:

```cpp
VAMP_LOG("Mission_Capture: spy self-steal, deferring target until vanilla SetDestination");
return 0;
```

- [x] **Step 2: Add the post-destination hook**

Insert after the `0x4D4B43` hook:

```cpp
DEFINE_HOOK(0x4D4BC7, FootClass_Mission_Capture_SetSpyTargetAfterDestination, 0x6)
{
    GET(InfantryClass*, pThis, EDI);

    if (!pThis || pThis->Target)
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Destination);
    if (!pBld || pBld->IsStrange() || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    VAMP_LOG("Mission_Capture: spy self-steal, setting target after vanilla SetDestination");
    pThis->SetTarget(pBld);
    return 0;
}
```

- [x] **Step 3: Run the check and verify GREEN**

Run:

```powershell
& 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

### Task 3: Build and deploy the diagnostic DLL

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Build Win32 Release**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /p:Configuration=Release /p:Platform=Win32 /m
```

Expected: `0 Error(s)`.

- [x] **Step 2: Build Win32 Debug**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /p:Configuration=Debug /p:Platform=Win32 /m
```

Expected: `0 Error(s)`.

- [x] **Step 3: Verify no game process is running and deploy**

Check `gamemd`, `Syringe`, and process paths containing `AGWar1.3.1`. Back up the installed DLL and current log with timestamped names, copy `bin\Debug\Ra2.Vampire.Extend.dll` into the game root, then compare SHA256 values.

Expected: no matching process and identical source/destination SHA256 values.

- [x] **Step 4: Inspect the final diff without committing**

Review only the design document, implementation plan, test script, and `dllmain.cpp`. Do not create a commit because the target project is currently an untracked subtree of a broader working tree and the user requested direct deployment.
