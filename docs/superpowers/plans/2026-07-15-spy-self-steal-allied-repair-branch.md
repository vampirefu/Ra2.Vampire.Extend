# Spy Self-Steal Allied Repair Branch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a strict spy that has followed a planning path into a damaged friendly `Spyable` building bypass the allied repair branch and execute normal infiltration.

**Architecture:** Add one narrowly scoped Syringe hook over the complete `test al, al` / `jne 0x519FA2` block at `0x519D53`. The hook validates the strict friendly-spy scenario and redirects only that case to the existing `0x519FF8` infiltration gate, preserving the Phobos hook at `0x51A002` and leaving all path, mission, engineer, and enemy-infiltration behavior unchanged.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Add the allied-repair-branch regression constraint

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Add assertions for the new hook**

Insert the following before the existing `0x519FF8` assertions:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519D53,\s*InfantryClass_UpdatePosition_BypassAlliedRepairForSpySelfSteal,\s*0x8\)' `
    -Message 'Missing allied repair branch bypass hook at 0x519D53.'

$alliedRepairHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519D53,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' `
    -Message 'The allied repair hook must read InfantryClass this from ESI.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'GET\(BuildingClass\*,\s*pBuilding,\s*EDI\);' `
    -Message 'The allied repair hook must read the reached building from EDI.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern '!IsCandidateSpy\(pThis\)\s*\|\|\s*!IsSpySelfStealScenario\(pThis,\s*pBuilding\)' `
    -Message 'The allied repair bypass must require a strict friendly spy scenario.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'ContinueToInfiltrationGate\s*=\s*0x519FF8' `
    -Message 'The allied repair bypass must reuse the existing infiltration gate.'

foreach ($pattern in @(
    'SetTarget\(',
    'SetDestination\(',
    'QueueMission\(',
    'NextMission\(',
    'ClearNavigationList\(',
    'ApproachTarget\(',
    'InfiltratedBy\('
)) {
    if ($alliedRepairHook -match $pattern) {
        throw "The allied repair hook must only redirect control flow; found: $pattern"
    }
}
```

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: the command fails with `Missing allied repair branch bypass hook at 0x519D53.`

### Task 2: Implement the minimal control-flow bypass

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Add the `0x519D53` hook**

Insert this hook immediately before the existing `0x519FF8` hook and renumber only the explanatory hook comments:

```cpp
// ===========================================================================
// 钩子3: InfantryClass::UpdatePosition 友军维修分支
// 地址: 0x519D53, 大小: 0x8
// 原始指令:
//   0x519D53: test al, al
//   0x519D55: jne 0x519FA2
//
// 友军残血建筑会走到 0x519FA2 的维修逻辑，从而绕过 0x519FF8 的渗透门。
// 只对严格间谍自偷场景转到现有渗透门，其他情况执行原始分支。
// ===========================================================================
DEFINE_HOOK(0x519D53, InfantryClass_UpdatePosition_BypassAlliedRepairForSpySelfSteal, 0x8)
{
    enum { ContinueToInfiltrationGate = 0x519FF8 };

    GET(InfantryClass*, pThis, ESI);
    GET(BuildingClass*, pBuilding, EDI);

    if (!IsCandidateSpy(pThis) || !IsSpySelfStealScenario(pThis, pBuilding))
        return 0;

    VAMP_LOG("UpdatePosition allied repair branch: spy self-steal, continuing to infiltration gate");
    return ContinueToInfiltrationGate;
}
```

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 3: Inspect the focused source diff**

Run:

```powershell
git diff -- 'tests/check-spy-self-steal.ps1' 'Ra2.Vampire.Extend/dllmain.cpp'
```

Expected: only the regression assertions and one `0x519D53` hook are newly added; there are no Phobos changes and no path or mission mutations.

### Task 3: Build both Win32 configurations

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Output: `bin/Release/Ra2.Vampire.Extend.dll`
- Output: `bin/Debug/Ra2.Vampire.Extend.dll`

- [x] **Step 1: Build Release**

Run:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /p:Configuration=Release /p:Platform=Win32 /m
```

Expected: build succeeds with `0 Error(s)`.

- [x] **Step 2: Build Debug**

Run:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /p:Configuration=Debug /p:Platform=Win32 /m
```

Expected: build succeeds with `0 Error(s)`.

- [x] **Step 3: Re-run the source check after both builds**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

### Task 4: Deploy the Debug DLL safely

**Files:**
- Source: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`
- Back up: installed DLL and `Ra2.Vampire.Extend.log`

- [x] **Step 1: Refuse deployment while the game directory is in use**

Run:

```powershell
$gameDir = 'C:\Users\Vampire\Desktop\AGWar1.3.1'
$running = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($gameDir, [System.StringComparison]::OrdinalIgnoreCase)
}
if ($running) {
    $running | Select-Object Name, ProcessId, ExecutablePath | Format-Table -AutoSize
    throw 'AGWar 1.3.1 is still running; deployment aborted.'
}
```

Expected: no matching process. If a process is listed, stop without copying or backing up anything.

- [x] **Step 2: Back up the installed DLL and log, then deploy Debug**

Run only after Step 1 succeeds:

```powershell
$sourceDll = 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\bin\Debug\Ra2.Vampire.Extend.dll'
$targetDll = Join-Path $gameDir 'Ra2.Vampire.Extend.dll'
$targetLog = Join-Path $gameDir 'Ra2.Vampire.Extend.log'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (Test-Path -LiteralPath $targetDll) {
    Copy-Item -LiteralPath $targetDll -Destination "$targetDll.bak-allied-repair-$stamp"
}
if (Test-Path -LiteralPath $targetLog) {
    Copy-Item -LiteralPath $targetLog -Destination "$targetLog.bak-allied-repair-$stamp"
}

Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $targetDll -Algorithm SHA256).Hash
[pscustomobject]@{
    SourceSHA256 = $sourceHash
    TargetSHA256 = $targetHash
    Match = $sourceHash -eq $targetHash
}
if ($sourceHash -ne $targetHash) {
    throw 'Deployed DLL hash mismatch.'
}
```

Expected: `Match` is `True`.

### Task 5: Final verification and handoff

**Files:**
- Review: `Ra2.Vampire.Extend/dllmain.cpp`
- Review: `tests/check-spy-self-steal.ps1`
- Review: `docs/superpowers/specs/2026-07-15-spy-self-steal-allied-repair-branch-design.md`
- Review: `docs/superpowers/plans/2026-07-15-spy-self-steal-allied-repair-branch.md`

- [x] **Step 1: Verify Phobos remains untouched**

Run:

```powershell
git -C 'E:\WorkSpace\cncnet\phobos-release' status --short
```

Expected: no changes created by this plan. Pre-existing changes, if any, must be reported without modification.

- [x] **Step 2: Record final hashes and focused status**

Run:

```powershell
Get-FileHash -Algorithm SHA256 `
    'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\bin\Debug\Ra2.Vampire.Extend.dll', `
    'C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll'
git status --short -- `
    'Ra2.Vampire.Extend/dllmain.cpp' `
    'tests/check-spy-self-steal.ps1' `
    'docs/superpowers/specs/2026-07-15-spy-self-steal-allied-repair-branch-design.md' `
    'docs/superpowers/plans/2026-07-15-spy-self-steal-allied-repair-branch.md'
```

Expected: the two hashes match. Do not commit because this project is an untracked subtree in the current workspace and the established workflow is direct test deployment.

- [x] **Step 3: Request the exact game reproduction**

Ask the user to launch AGWar 1.3.1 and reproduce: select engineer plus spy, queue path point A, then queue the damaged friendly `Spyable` barracks. Expected: both pass A, the engineer enters, the spy also enters and triggers infiltration, and the game remains stable.
