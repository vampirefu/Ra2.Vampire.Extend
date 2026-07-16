# Spy Self-Steal Explicit Branch Crash Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the engineer crash at the `0x519D53` hook while preserving the friendly spy redirect to the existing infiltration gate.

**Architecture:** Keep the existing hook address and size, capture the original `AL` allied result, and explicitly return one of the two vanilla destinations or the friendly-spy infiltration destination. Never return `0` from this hook, so Syringe does not execute the saved relative conditional jump.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with unmodified Phobos.

---

### Task 1: Add failing explicit-branch constraints

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require the saved condition and all three destinations**

Add these assertions after the existing `ContinueToInfiltrationGate` assertion:

```powershell
Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'wasAllied\s*=\s*R->AL\(\)\s*!=\s*0' `
    -Message 'The allied repair hook must save the original AL result.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'ContinueOriginalNonAllied\s*=\s*0x519D5B' `
    -Message 'Missing explicit vanilla non-allied continuation at 0x519D5B.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'ContinueOriginalAllied\s*=\s*0x519FA2' `
    -Message 'Missing explicit vanilla allied continuation at 0x519FA2.'

Assert-Contains `
    -Text $alliedRepairHook `
    -Pattern 'wasAllied\s*\?\s*ContinueOriginalAllied\s*:\s*ContinueOriginalNonAllied' `
    -Message 'Non-spy execution must explicitly reproduce the original test/jne branch.'

if ($alliedRepairHook -match 'return\s+0\s*;') {
    throw 'The allied repair hook must not return 0 through Syringe saved relative code.'
}
```

- [x] **Step 2: Run the source check and verify RED**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: failure with `The allied repair hook must save the original AL result.`

### Task 2: Replace the unsafe fallback with explicit branching

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp:207`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Replace only the body of the `0x519D53` hook**

Use this implementation:

```cpp
DEFINE_HOOK(0x519D53, InfantryClass_UpdatePosition_BypassAlliedRepairForSpySelfSteal, 0x8)
{
    enum
    {
        ContinueOriginalNonAllied = 0x519D5B,
        ContinueOriginalAllied = 0x519FA2,
        ContinueToInfiltrationGate = 0x519FF8
    };

    GET(InfantryClass*, pThis, ESI);
    GET(BuildingClass*, pBuilding, EDI);

    auto const wasAllied = R->AL() != 0;

    if (IsCandidateSpy(pThis) && IsSpySelfStealScenario(pThis, pBuilding))
    {
        VAMP_LOG("UpdatePosition allied repair branch: spy self-steal, continuing to infiltration gate");
        return ContinueToInfiltrationGate;
    }

    return wasAllied ? ContinueOriginalAllied : ContinueOriginalNonAllied;
}
```

- [x] **Step 2: Run the source check and verify GREEN**

Run:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tests\check-spy-self-steal.ps1'
```

Expected: `Spy self-steal source checks passed.`

- [x] **Step 3: Inspect the hook and forbidden mutations**

Run:

```powershell
rg -n -A 30 'DEFINE_HOOK\(0x519D53' 'Ra2.Vampire.Extend\dllmain.cpp'
```

Expected: the hook has exactly three explicit destinations, no `return 0`, and no target, path, mission, or direct infiltration mutation.

### Task 3: Rebuild and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Source artifact: `bin/Debug/Ra2.Vampire.Extend.dll`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Rebuild Win32 Release**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0`.

- [x] **Step 2: Rebuild Win32 Debug**

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\Ra2.Vampire.Extend.sln' /t:Rebuild /p:Configuration=Debug /p:Platform=Win32 /m /nologo /v:minimal
```

Expected: exit code `0`.

- [x] **Step 3: Verify processes, back up, and deploy**

```powershell
$ErrorActionPreference = 'Stop'
$gameDir = (Resolve-Path -LiteralPath 'C:\Users\Vampire\Desktop\AGWar1.3.1').Path
$sourceDll = (Resolve-Path -LiteralPath 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\bin\Debug\Ra2.Vampire.Extend.dll').Path
$targetDll = Join-Path $gameDir 'Ra2.Vampire.Extend.dll'
$targetLog = Join-Path $gameDir 'Ra2.Vampire.Extend.log'
$running = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($gameDir, [System.StringComparison]::OrdinalIgnoreCase)
}
if ($running) {
    $running | Select-Object Name, ProcessId, ExecutablePath | Format-Table -AutoSize
    throw 'AGWar 1.3.1 is running; deployment aborted.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $targetDll -Destination "$targetDll.bak-explicit-branch-$stamp"
if (Test-Path -LiteralPath $targetLog) {
    Copy-Item -LiteralPath $targetLog -Destination "$targetLog.bak-explicit-branch-$stamp"
}
Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $targetDll -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) {
    throw 'Deployed DLL hash mismatch.'
}
[pscustomobject]@{ SourceSHA256 = $sourceHash; TargetSHA256 = $targetHash; Match = $true }
```

Expected: no matching process and `Match` is `True`.

- [x] **Step 4: Run final automated verification**

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

Expected: source checks pass, hashes match, and both Phobos diff commands return zero. Do not commit or create a worktree.

### Task 4: Request runtime verification

**Files:**
- Inspect after test: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.log`
- Inspect on failure: `C:\Users\Vampire\Desktop\AGWar1.3.1\debug\debug.log`

- [x] **Step 1: Reproduce the exact scenario**

Ask the user to queue engineer plus spy through A into the damaged friendly `Spyable` barracks. Expected: engineer enters without a crash, then spy reaches the infiltration gate and enters the same building.
