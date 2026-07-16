# Spy Self-Steal Post-SetDestination Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a temporary read-only runtime trace at `0x4D4BC7` that proves whether vanilla `Mission_Capture` preserved the friendly spy's reconstructed building destination.

**Architecture:** Keep the existing three behavior hooks unchanged. Add one filtered diagnostic hook immediately after vanilla's `SetDestination(Target, true)` join point, log the spy's target/destination and mission state, and return normal control without mutating gameplay state. Temporarily teach the source checker to require and constrain this diagnostic hook.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Specify the temporary diagnostic hook

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Stop treating `0x4D4BC7` as forbidden**

Change the final-build forbidden address array from:

```powershell
foreach ($address in @('0x4D4B43', '0x4D4BC7', '0x4C7462', '0x519D53', '0x709A40', '0x709A63', '0x709A71', '0x6385C0')) {
```

to:

```powershell
foreach ($address in @('0x4D4B43', '0x4C7462', '0x519D53', '0x709A40', '0x709A63', '0x709A71', '0x6385C0')) {
```

- [x] **Step 2: Require the filtered read-only state trace**

Insert these checks immediately after the prehook checks and before the remaining forbidden-address loop:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x4D4BC7,\s*FootClass_Mission_Capture_LogSpyDestinationState,\s*0x6\)' `
    -Message 'Missing post-SetDestination Mission_Capture diagnostic hook at 0x4D4BC7.'

$postSetDestinationHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x4D4BC7,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $postSetDestinationHook `
    -Pattern 'GET\(FootClass\*,\s*pFoot,\s*ESI\);' `
    -Message 'The 0x4D4BC7 diagnostic hook must read FootClass this from ESI.'

Assert-Contains `
    -Text $postSetDestinationHook `
    -Pattern 'IsCandidateSpy\(pThis\)' `
    -Message 'The post-SetDestination trace must only inspect strict spies.'

Assert-Contains `
    -Text $postSetDestinationHook `
    -Pattern 'specific_cast<BuildingClass\*>\(pThis->Target\)' `
    -Message 'The post-SetDestination trace must validate the building from Target.'

Assert-Contains `
    -Text $postSetDestinationHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBld\)' `
    -Message 'The post-SetDestination trace must only inspect friendly Spyable targets.'

Assert-Contains `
    -Text $postSetDestinationHook `
    -Pattern 'Mission_Capture post-SetDestination: this=%p target=%p destination=%p current=%d queued=%d status=%d' `
    -Message 'The diagnostic hook must log target, destination, and mission state.'

foreach ($pattern in @('SetDestination\(', 'SetTarget\(', 'QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(')) {
    if ($postSetDestinationHook -match $pattern) {
        throw "The post-SetDestination diagnostic hook must remain read-only; found: $pattern"
    }
}
```

- [x] **Step 3: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: failure with `Missing post-SetDestination Mission_Capture diagnostic hook at 0x4D4BC7.` This proves the new check detects the missing instrumentation.

### Task 2: Add the minimal read-only hook

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp:198`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Add the post-SetDestination diagnostic hook**

Insert this hook between the existing `0x4D4B20` prehook and `0x519FF8` infiltration hook:

```cpp
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
```

Do not alter the behavior of the existing `0x51EE4E`, `0x4D4B20`, or `0x519FF8` hooks.

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 3: Inspect the exact hook body**

Run:

```powershell
rg -n -A 40 'DEFINE_HOOK\(0x4D4BC7' 'Ra2.Vampire.Extend\dllmain.cpp'
```

Expected: the body only validates objects, writes one filtered log line, and returns `0`; none of the forbidden mutation calls appear.

### Task 3: Build and deploy the diagnostic DLL

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Source artifact: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Release and Debug for Win32**

Run both configurations:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Debug /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: each command exits with code `0` and reports no compiler errors.

- [x] **Step 2: Guard, back up, and deploy**

Run:

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
Copy-Item -LiteralPath $targetDll -Destination "$targetDll.bak-postdest-$stamp"
if (Test-Path -LiteralPath $targetLog) {
    Copy-Item -LiteralPath $targetLog -Destination "$targetLog.bak-postdest-$stamp"
}
Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $targetDll -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) { throw 'Deployed DLL hash mismatch.' }
Write-Output "deployed_sha256=$targetHash"
```

Expected: no game process is running, timestamped backups are created, and the source/deployed hashes match.

- [x] **Step 3: Run final automated verification**

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

Expected: source check passes, hashes match, and both Phobos checks return zero. Do not create a worktree or commit.

### Task 4: Capture and interpret one runtime trace

**Files:**
- Inspect: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log`

- [x] **Step 1: Reproduce the waypoint path**

Select the engineer and spy, queue waypoint A, then queue the damaged friendly `Spyable` barracks. End the short test after the units settle or the spy enters.

- [x] **Step 2: Read only the newest diagnostic sequence**

Run:

```powershell
Get-Content -LiteralPath 'C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log' -Tail 300
```

Expected sequence starts with:

```text
Mission_Capture prehook: reactivating friendly spy destination before Phobos
Mission_Capture post-SetDestination: this=... target=... destination=... current=... queued=... status=...
```

Interpret the first post-SetDestination line using the design rules: equal non-null target/destination means reconstruction succeeded; null destination means it did not persist; a missing post line means control did not reach `0x4D4BC7`. A later `UpdatePosition EC4 check` means the spy reached the final infiltration branch.
