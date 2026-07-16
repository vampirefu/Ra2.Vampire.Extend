# Spy Self-Steal Planning Advance Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log every decision boundary between reaching waypoint A and consuming the queued Capture planning node.

**Architecture:** Add four read-only Syringe hooks around `ProceedToNextPlanningWaypoint`, `RefreshMegaMission`, `CanUseWaypoint`, and `TryNextPlanningTokenNode`, using one helper to log comparable PlanningToken state for engineers and strict spies.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1.

---

### Task 1: Add failing source constraints

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] Require hooks at `0x709A40` size `0x9`, `0x709A63` size `0x6`, `0x709A71` size `0x6`, and `0x6385C0` size `0x6`.
- [x] Require a `Planning advance:` log with stage, result, token nodes/flags and mission/path state.
- [x] Isolate all four hook bodies and reject `SetTarget`, `SetDestination`, `QueueMission`, `NextMission`, `ClearNavigationList`, `ApproachTarget`, or `TryNextPlanningTokenNode` calls.
- [x] Run `tests/check-spy-self-steal.ps1` and expect failure for the missing `0x709A40` hook.

### Task 2: Implement read-only planning diagnostics

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] Add a helper that accepts only engineer or strict-spy infantry.
- [x] Add a logging helper that safely handles a null PlanningToken and records the approved fields.
- [x] Add the four hooks with the verified registers and pass `AL` as result at the two return-value boundaries.
- [x] Run the source check and expect `Spy self-steal source checks passed.`

### Task 3: Build and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] Build `Release|Win32` and `Debug|Win32`; expect zero warnings and zero errors.
- [x] Confirm no game process is running, back up the installed DLL/log, copy Debug DLL, and verify matching SHA256.
- [x] Preserve the current main working tree without committing or cleaning unrelated files.
