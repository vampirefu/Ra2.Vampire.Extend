# Spy Self-Steal MegaMission Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the exact planning MegaMission assigned to the engineer and spy without mutating game state.

**Architecture:** Remove the failed post-destination target injection, classify spies with `Agent && Infiltrate && !Engineer`, and log per-unit MegaMission data at the Phobos-verified `0x4C7462` execution boundary.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1.

---

### Task 1: Define diagnostic source constraints

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Require strict spy identification and the MegaMission hook**

Require `IsCandidateSpy` to check `Agent`, `Infiltrate`, and `!Engineer`. Require `DEFINE_HOOK(0x4C7462, EventClass_Execute_MegaMission_SpySelfStealDiagnostics, 0x5)`, `EDI` for the receiving techno, `ESI` for the event, and a `MegaMission dispatch:` log containing mission, target, destination, follow, planning, current/queued mission, planning token, path, waypoint, and navigation count.

- [x] **Step 2: Forbid failed Mission_Capture mutation**

Require no `0x4D4BC7` hook and isolate the `0x4D4B43` hook to assert it contains none of `SetTarget`, `SetDestination`, `QueueMission`, `NextMission`, `ClearNavigationList`, or `ApproachTarget`.

- [x] **Step 3: Run the source check and verify RED**

Run:

```powershell
& 'E:\WorkSpace\cncnet\Ra2.Vampire.Extend\tests\check-spy-self-steal.ps1'
```

Expected: failure because the MegaMission diagnostics hook does not exist yet.

### Task 2: Implement read-only command diagnostics

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] **Step 1: Tighten spy classification**

Use:

```cpp
return pThis && pThis->Type
    && pThis->Type->Agent
    && pThis->Type->Infiltrate
    && !pThis->Type->Engineer;
```

- [x] **Step 2: Make Mission_Capture observational**

Keep the `0x4D4B43` hook only to log strict-spy entry state and return `0`. Remove the entire `0x4D4BC7` hook.

- [x] **Step 3: Add MegaMission diagnostics**

At `0x4C7462`, read `TechnoClass*` from `EDI` and `EventClass*` from `ESI`. For infantry whose type is `Engineer` or a strict spy, resolve the event target classes and emit all approved diagnostic fields, then return `0`.

- [x] **Step 4: Run the source check and verify GREEN**

Run the same PowerShell check. Expected: `Spy self-steal source checks passed.`

### Task 3: Build and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] **Step 1: Build Win32 Release and Debug**

Run MSBuild separately for `Release|Win32` and `Debug|Win32`. Expected for both: zero errors.

- [x] **Step 2: Deploy after process safety check**

Confirm no AGWar, gamemd, or Syringe process is running. Back up the installed DLL and current log, copy the Debug DLL, and verify identical SHA256 values.

- [x] **Step 3: Preserve the working tree**

Do not commit or clean unrelated files; this is an in-place diagnostic deployment requested by the user.
