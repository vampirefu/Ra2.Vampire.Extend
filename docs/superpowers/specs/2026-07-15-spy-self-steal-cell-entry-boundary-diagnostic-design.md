# Spy Self-Steal Cell-Entry Boundary Diagnostic Design

## Purpose

Determine whether the friendly spy starts moving after `Mission_Capture` reconstructs its destination, and identify the last map cell it reaches before failing to enter the target barracks.

The preceding runtime trace proves that `Target` and `Destination` both point to the same friendly `Spyable` barracks while `CurrentMission` is `Mission::Capture`. Vanilla `InfantryClass::UpdatePosition` reaches the existing `0x519FF8` infiltration gate only after a newly entered cell resolves to the destination building. Because `0x519FF8` was not reached, the unresolved boundary is movement into the building cell rather than Capture initialization or final infiltration.

## Selected Approach

Keep the existing filtered `0x4D4BC7` state trace and add one temporary read-only hook at `0x519948`.

Address `0x519948` is the start of the mission gate executed when `InfantryClass::UpdatePosition` processes a position change. Its original ten bytes obtain the infantry's current mission. A size-`0xA` Syringe hook can observe state and then return normal control so those original instructions still execute.

The hook will:

- read `InfantryClass*` from `ESI`;
- require a strict spy in `Mission::Capture`;
- obtain the friendly `Spyable` building from `Destination`;
- read the spy and destination building map cells through `GetMapCoords()`;
- log `Target`, `Destination`, the two cell coordinates, `QueuedMission`, and `MissionStatus`;
- return `0` without changing registers, target, destination, navigation, mission, locomotor, or occupancy results.

The trace is deliberately emitted once per qualifying position-change pass. This preserves the chronological route and avoids pointer-based diagnostic state that could become stale.

## Alternatives Rejected

1. Paired entry/exit hooks around `InfantryClass::IsCellOccupied` would expose the exact occupancy return value, but require call correlation and stack-sensitive return instrumentation with higher crash risk.
2. Logging locomotor state immediately after `SetDestination` would show whether a command was accepted, but would not reveal a later stop at a specific cell.

## Test and Safety Constraints

The PowerShell source check will require the exact `0x519948` hook, `ESI` register source, Capture/scenario filters, coordinate log, and a `return 0`. It will reject calls that mutate state, including `SetDestination`, `SetTarget`, `QueueMission`, `NextMission`, `ClearNavigationList`, `ApproachTarget`, and locomotor movement commands.

Release and Debug Win32 builds must both succeed. Deployment must stop if an AGWar process from the game directory is running. The deployed Debug DLL hash must match the build artifact. Phobos tracked and staged diffs must remain empty.

## Runtime Interpretation

- No `UpdatePosition Capture movement` line after `post-SetDestination`: the new destination did not start a qualifying position change, so investigation moves to locomotor command setup.
- Movement lines whose final spy cell differs from the building cell, followed by no `0x519FF8` line: movement stopped before entering the destination cell, so investigation moves to path/occupancy acceptance for the final step.
- A movement line where the spy cell equals the building cell but no `0x519FF8` line follows: `UpdatePosition` failed to resolve that cell to the destination building, so investigation stays inside its cell/object matching branch.
- A subsequent `UpdatePosition EC4 check` line: the spy reached the final infiltration gate; the remaining outcome is in the final infiltration/Phobos continuation.

## Lifecycle

This hook is temporary instrumentation and will be removed after one useful trace identifies the next failing boundary. The implementation does not modify Phobos, create a worktree, or create a commit.
