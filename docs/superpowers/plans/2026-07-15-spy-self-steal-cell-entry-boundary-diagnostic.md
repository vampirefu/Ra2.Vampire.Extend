# Spy Self-Steal Cell-Entry Boundary Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a temporary read-only `0x519948` trace that records each qualifying spy position-change cell and identifies whether movement reaches the friendly barracks cell.

**Architecture:** Preserve all existing behavior and diagnostic hooks. Add one strictly filtered observer at the `InfantryClass::UpdatePosition` mission gate, record unit/destination map cells, and return normal control so vanilla executes the overwritten current-mission instructions. Extend the PowerShell checker to require the hook and reject gameplay mutations inside it.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Specify the movement boundary trace

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require the exact filtered hook**

Insert the following checks after the existing `$postSetDestinationHook` checks:

```powershell
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519948,\s*InfantryClass_UpdatePosition_LogSpyCaptureMovement,\s*0xA\)' `
    -Message 'Missing Capture movement diagnostic hook at 0x519948.'

$captureMovementHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519948,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' `
    -Message 'The 0x519948 diagnostic hook must read InfantryClass this from ESI.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'IsCandidateSpy\(pThis\)[\s\S]*pThis->CurrentMission\s*!=\s*Mission::Capture' `
    -Message 'The movement trace must require a strict spy in Mission::Capture.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'specific_cast<BuildingClass\*>\(pThis->Destination\)' `
    -Message 'The movement trace must obtain the building from Destination.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBld\)' `
    -Message 'The movement trace must only inspect the friendly Spyable scenario.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'unitCell\s*=\s*pThis->GetMapCoords\(\);[\s\S]*destinationCell\s*=\s*pBld->GetMapCoords\(\);' `
    -Message 'The movement trace must read unit and destination map cells.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'UpdatePosition Capture movement: this=%p target=%p destination=%p unitCell=\(%d,%d\) destinationCell=\(%d,%d\) queued=%d status=%d' `
    -Message 'The movement trace must log both cells and mission state.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'return\s+0;' `
    -Message 'The movement trace must return normal control.'

foreach ($pattern in @('SetDestination\(', 'SetTarget\(', 'QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(', 'StopMoving\(', 'Locomotor->')) {
    if ($captureMovementHook -match $pattern) {
        throw "The Capture movement diagnostic hook must remain read-only; found: $pattern"
    }
}
```

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: failure with `Missing Capture movement diagnostic hook at 0x519948.`

### Task 2: Add the minimal read-only observer

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp:231`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Insert the `0x519948` hook**

Insert this implementation between the existing `0x4D4BC7` diagnostic hook and the `0x519FF8` infiltration hook:

```cpp
// ===========================================================================
// Temporary diagnostic: Capture movement cell boundary
// Address: 0x519948, size: 0xA
// Original instructions obtain the current mission from ESI = InfantryClass*.
// ===========================================================================
DEFINE_HOOK(0x519948, InfantryClass_UpdatePosition_LogSpyCaptureMovement, 0xA)
{
    GET(InfantryClass*, pThis, ESI);

    if (!IsCandidateSpy(pThis) || pThis->CurrentMission != Mission::Capture)
        return 0;

    auto const pBld = specific_cast<BuildingClass*>(pThis->Destination);
    if (!pBld || pBld->IsStrange() || !IsSpySelfStealScenario(pThis, pBld))
        return 0;

    auto const unitCell = pThis->GetMapCoords();
    auto const destinationCell = pBld->GetMapCoords();
    VAMP_LOG(
        "UpdatePosition Capture movement: this=%p target=%p destination=%p unitCell=(%d,%d) destinationCell=(%d,%d) queued=%d status=%d",
        pThis,
        pThis->Target,
        pThis->Destination,
        static_cast<int>(unitCell.X),
        static_cast<int>(unitCell.Y),
        static_cast<int>(destinationCell.X),
        static_cast<int>(destinationCell.Y),
        static_cast<int>(pThis->QueuedMission),
        pThis->MissionStatus);

    return 0;
}
```

Do not change the existing `0x51EE4E`, `0x4D4B20`, `0x4D4BC7`, or `0x519FF8` implementations.

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 3: Inspect the focused hook and address ownership**

Run:

```powershell
rg -n -A 45 'DEFINE_HOOK\(0x519948' 'Ra2.Vampire.Extend\dllmain.cpp'
rg -n -i '0x0*519948|519948' 'E:\WorkSpace\cncnet\phobos-release\src' 'E:\WorkSpace\cncnet\phobos-release\.agents'
```

Expected: the local hook contains no forbidden mutation; the Phobos/Ares reference search has no match.

### Task 3: Build and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Source artifact: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Release and Debug for Win32**

Run:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Debug /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: both commands exit with code `0` and report no compiler errors.

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
Copy-Item -LiteralPath $targetDll -Destination "$targetDll.bak-cellboundary-$stamp"
if (Test-Path -LiteralPath $targetLog) {
    Copy-Item -LiteralPath $targetLog -Destination "$targetLog.bak-cellboundary-$stamp"
}
Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $targetDll -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) { throw 'Deployed DLL hash mismatch.' }
Write-Output "deployed_sha256=$targetHash"
```

Expected: the game is not running, backups are created, and hashes match.

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

### Task 4: Capture one movement trace

**Files:**
- Inspect: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log`

- [x] **Step 1: Reproduce the same route**

Select engineer and spy, queue waypoint A, then queue the damaged friendly `Spyable` barracks. Stop after the spy settles or enters.

- [x] **Step 2: Read and classify the newest sequence**

Run:

```powershell
Get-Content -LiteralPath 'C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log' -Tail 400
```

Expected sequence begins with `Mission_Capture post-SetDestination` and is followed by zero or more `UpdatePosition Capture movement` entries. Classify it exactly as specified in the design: no movement lines means locomotor setup failure; a final cell different from the destination cell means final-step path/occupancy failure; equal cells without `UpdatePosition EC4 check` means cell/object matching failure; `UpdatePosition EC4 check` means the final infiltration gate was reached.
