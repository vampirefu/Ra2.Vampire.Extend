# Spy Self-Steal Phobos Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the friendly spy building destination before Phobos rejects allied infiltration, allowing the queued Capture node to execute.

**Architecture:** Set the validated friendly building as the strict spy's Target at the conflict-free `Mission_Capture` entry `0x4D4B20`, before Phobos reaches its `0x4D4B43` hook. Remove all same-address and diagnostic hooks.

**Tech Stack:** C++20, YRPP/Syringe hooks, PowerShell source checks, MSBuild Win32, AGWar 1.3.1 with Phobos.

---

### Task 1: Replace diagnostic assertions with compatibility assertions

**Files:**
- Modify: `tests/check-spy-self-steal.ps1`
- Test: `tests/check-spy-self-steal.ps1`

- [x] Require `DEFINE_HOOK(0x4D4B20, FootClass_Mission_Capture_PrepareSpySelfSteal, 0x6)` and `GET(FootClass*, pFoot, ECX)`.
- [x] Require strict infantry/spy validation, building extraction from `Destination`, self-steal validation and `SetTarget(pBld)`.
- [x] Reject hooks at `0x4D4B43`, `0x4D4BC7`, `0x4C7462`, `0x709A40`, `0x709A63`, `0x709A71`, and `0x6385C0`.
- [x] Reject path and mission mutations inside the prehook.
- [x] Run the PowerShell check and verify RED for the missing `0x4D4B20` hook.

### Task 2: Implement the compatibility prehook

**Files:**
- Modify: `Ra2.Vampire.Extend/dllmain.cpp`
- Test: `tests/check-spy-self-steal.ps1`

- [x] Remove `EventClass.h`, diagnostic helpers and all diagnostic hooks.
- [x] Add the `0x4D4B20` hook using `ECX`, validate the strict spy scenario, set Target once and return `0`.
- [x] Keep `WhatAction` and `UpdatePosition` behavior unchanged.
- [x] Run the PowerShell check and verify GREEN.

### Task 3: Build and deploy

**Files:**
- Build: `Ra2.Vampire.Extend.sln`
- Deploy: `C:\Users\Vampire\Desktop\AGWar1.3.1\Ra2.Vampire.Extend.dll`

- [x] Build `Release|Win32` and `Debug|Win32`; require zero warnings and zero errors.
- [x] Verify no game process is running, back up the current DLL/log, deploy Debug and compare SHA256.
- [x] Preserve the main working tree without commits or unrelated cleanup.
