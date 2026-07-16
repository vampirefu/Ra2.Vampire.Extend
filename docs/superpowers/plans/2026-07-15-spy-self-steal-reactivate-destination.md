# Spy Self-Steal Reactivate Capture Destination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the spy's normal Capture entry state after waypoint A so it can enter a damaged friendly `Spyable` building.

**Architecture:** At the existing pre-Phobos `0x4D4B20` hook, clear the queued planning Destination once and then set the building as Target. Phobos permits the non-null Target, vanilla `Mission_Capture` sees a null Destination and calls `SetDestination(Target, true)` itself; remove the SPY-unreachable `0x519D53` hook.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Replace the obsolete branch-hook constraints

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require one-time Destination reactivation**

After extracting `$preHook`, require this order and exact call count:

```powershell
Assert-Contains `
    -Text $preHook `
    -Pattern 'pThis->SetDestination\(nullptr,\s*false\);[\s\S]*pThis->SetTarget\(pBld\);' `
    -Message 'The pre-Phobos hook must clear the queued Destination before setting Target.'

$clearDestinationCount = [regex]::Matches($preHook, 'pThis->SetDestination\(nullptr,\s*false\);').Count
if ($clearDestinationCount -ne 1) {
    throw "Expected exactly one one-time Destination clear in the prehook, found $clearDestinationCount."
}
```

Change the prehook forbidden-operation list to:

```powershell
foreach ($pattern in @('QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(')) {
    if ($preHook -match $pattern) {
        throw "The pre-Phobos hook must not mutate paths or missions; found: $pattern"
    }
}
```

Update the expected log assertion to:

```powershell
Assert-Contains `
    -Text $preHook `
    -Pattern 'Mission_Capture prehook: reactivating friendly spy destination before Phobos' `
    -Message 'The compatibility hook must log the one-time Capture destination reactivation.'
```

- [x] **Step 2: Delete the `0x519D53` positive assertions and forbid the hook**

Remove the `$alliedRepairHook` extraction and all assertions for its registers, destinations, `R->AL()`, and forbidden operations. Add `0x519D53` to the existing array of experimental/diagnostic addresses that must not appear in `DEFINE_HOOK`.

- [x] **Step 3: Run the source check and verify RED**

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: failure with `The pre-Phobos hook must clear the queued Destination before setting Target.`

### Task 2: Reactivate vanilla Capture setup

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp:177`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Change the one-time prehook mutation**

Replace the log and mutation tail of `FootClass_Mission_Capture_PrepareSpySelfSteal` with:

```cpp
VAMP_LOG("Mission_Capture prehook: reactivating friendly spy destination before Phobos");
pThis->SetDestination(nullptr, false);
pThis->SetTarget(pBld);
return 0;
```

The existing `!IsCandidateSpy(pThis) || pThis->Target` guard and friendly `Spyable` validation remain unchanged, so this executes only once after the Capture planning node becomes current.

- [x] **Step 2: Remove the complete `0x519D53` hook**

Delete the `InfantryClass_UpdatePosition_BypassAlliedRepairForSpySelfSteal` comment block and implementation. Update the file header to list three hooks and renumber the existing `0x519FF8` comment as hook 3. Do not alter the `0x519FF8` implementation.

- [x] **Step 3: Run the source check and verify GREEN**

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 4: Inspect the focused implementation**

```powershell
rg -n -A 35 'DEFINE_HOOK\(0x4D4B20' 'Ra2.Vampire.Extend\dllmain.cpp'
rg -n 'DEFINE_HOOK\(0x519D53|DEFINE_HOOK\(0x519FF8' 'Ra2.Vampire.Extend\dllmain.cpp'
```

Expected: `SetDestination(nullptr, false)` precedes `SetTarget(pBld)`, `0x519D53` is absent, and `0x519FF8` remains.

### Task 3: Rebuild and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Source artifact: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild both Win32 configurations**

Run Release and Debug separately or in parallel:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Debug /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: both commands exit with code `0`.

- [x] **Step 2: Back up and deploy after the process guard**

```powershell
$ErrorActionPreference = 'Stop'
$gameDir = (Resolve-Path -LiteralPath 'C:\Users\Vampire\Desktop\AGWar1.3.1').Path
$sourceDll = (Resolve-Path -LiteralPath 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\bin\Debug\Ra2.Vampire.Extend.dll').Path
$targetDll = Join-Path $gameDir 'Ra2.Vampire.Extend.dll'
$targetLog = Join-Path $gameDir 'Ra2.Vampire.Extend.log'
$running = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($gameDir, [System.StringComparison]::OrdinalIgnoreCase)
}
if ($running) { throw 'AGWar 1.3.1 is running; deployment aborted.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $targetDll -Destination "$targetDll.bak-reactivate-$stamp"
if (Test-Path -LiteralPath $targetLog) {
    Copy-Item -LiteralPath $targetLog -Destination "$targetLog.bak-reactivate-$stamp"
}
Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $targetDll -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) { throw 'Deployed DLL hash mismatch.' }
```

Expected: no running game process and matching SHA256 hashes.

- [x] **Step 3: Run final automated verification**

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

Expected: source check passes, hashes match, and both Phobos diff commands return zero. Do not commit or create a worktree.

### Task 4: Runtime verification

**Files:**
- Inspect after test: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log`

- [ ] **Step 1: Reproduce the same planning path**

Ask the user to select engineer plus spy, queue A, then queue the damaged friendly `Spyable` barracks. Expected: engineer enters without a crash; spy passes A, reaches `0x519FF8`, and enters the same building.
