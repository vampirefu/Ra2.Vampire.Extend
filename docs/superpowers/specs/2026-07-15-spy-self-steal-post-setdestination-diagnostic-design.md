# Spy Self-Steal Post-SetDestination Diagnostic Design

## Purpose

Determine why the spy never reaches the existing `0x519FF8` infiltration hook after the `0x4D4B20` compatibility hook reactivates a friendly building Capture target.

The 2026-07-15 21:46 runtime log proves that the new prehook executes once, but contains no `0x519FF8` entry. Vanilla `FootClass::Mission_Capture` disassembly shows that `0x4D4BB4` should call `SetDestination(Target, true)` before control reaches `0x4D4BC7`. The missing evidence is the actual object state immediately after that call.

## Selected Approach

Add a temporary read-only hook at `0x4D4BC7`, immediately after the vanilla `SetDestination(Target, true)` path rejoins `Mission_Capture`.

The hook will:

- read `FootClass*` from `ESI`;
- ignore null, non-infantry, non-spy, non-building, and non-friendly-`Spyable` cases;
- log `Target`, `Destination`, `CurrentMission`, `QueuedMission`, and `MissionStatus`;
- return normal control without changing registers, missions, navigation queues, targets, or destinations.

The log may repeat while the filtered spy remains in `Mission::Capture`. This is acceptable for one short reproduction and is safer than keeping pointer-based one-shot state that could become stale or collide with reused game objects.

## Alternatives Rejected

1. Hooking the global `SetDestination` implementation would reveal every call, but it has a wider collision and logging surface.
2. Logging the spy every frame would reveal later transitions, but would generate substantially more noise before the first boundary is understood.

## Test and Safety Constraints

The PowerShell source check will temporarily require the exact `0x4D4BC7` diagnostic hook and its state log. It will also reject mission/path mutations inside that hook, including `SetDestination`, `SetTarget`, `QueueMission`, `NextMission`, `ClearNavigationList`, and `ApproachTarget`.

Release and Debug Win32 builds must both succeed. Deployment is allowed only while no AGWar process from the game directory is running. The deployed Debug DLL hash must match the build artifact, and Phobos tracked and staged diffs must remain empty.

## Runtime Interpretation

- `Target == building` and `Destination == building`: vanilla destination reconstruction succeeded; the next investigation must follow later mission/navigation state changes.
- `Target == building` and `Destination == nullptr`: `SetDestination` did not persist; investigation remains inside the call or an overlapping hook.
- No `0x4D4BC7` diagnostic line after the prehook line: control left `Mission_Capture` before the expected join point, indicating a hook-chain or return-address issue.
- A subsequent `0x519FF8` line: the spy reached the building and the remaining result is in the final infiltration branch.

## Lifecycle

This hook is temporary diagnostic instrumentation. Once one runtime trace identifies the failing boundary, remove it or replace it only through a separately verified root-cause fix. Phobos remains unmodified, no worktree is created, and no commit is made.
