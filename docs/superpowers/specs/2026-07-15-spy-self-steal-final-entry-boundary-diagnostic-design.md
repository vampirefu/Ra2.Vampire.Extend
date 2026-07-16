# Spy Self-Steal Final Entry Boundary Diagnostic Design

## Purpose

Locate the exact final-step branch that prevents a stable friendly self-steal spy from reaching vanilla infiltration after the occupancy exception has already returned `Move::OK`.

## Runtime Evidence

The direct `CellClass::GetBuilding` correction removed the Debug crash. The latest run shows:

- `Mission_Capture` repeatedly preserves identical Target and Destination pointers;
- the strict `IsCellOccupied` exception fires 21 times;
- the spy advances from `(65,27)` as far as `(60,25)` toward the building anchor `(59,24)`;
- `UpdatePosition EC4 check` and `triggering infiltration` never appear;
- no new crash snapshot is created.

The occupancy rejection and thunk crash are therefore no longer the active boundary. Vanilla `InfantryClass::UpdatePosition` can still leave the entry flow in two places before the current-cell building identity checks.

## Selected Diagnostics

Add two temporary, strictly filtered, read-only hooks.

### Path-head completion observer at `0x519AFA`

Vanilla reaches `0x519AFA` after determining that the locomotor head-to coordinate resolves to the infantry's current cell while the infantry has not matched the Destination building map coordinates. The six-byte original instruction is:

```text
0x519AFA  mov eax,[esi+0x5A4]
```

At this point `ESI` is the `InfantryClass*`. The hook will require a strict spy in `Mission::Capture`, resolve its Destination building, and require `IsSpySelfStealScenario`. It will log the unit and destination cells, then return `0` so vanilla replays the complete instruction and continues unchanged.

Expected log:

```text
UpdatePosition path-head reached: this=%p target=%p destination=%p unitCell=(%d,%d) destinationCell=(%d,%d)
```

### Current-cell building lookup observer at `0x519B1B`

Vanilla reaches `0x519B1B` only when it continues past the path-head early-return branch. The five-byte original instruction is:

```text
0x519B1B  call 0x47C520
```

At this point `ESI` is the `InfantryClass*` and `ECX` is the current `CellClass*`. The hook will apply the same strict spy/scenario filter, invoke `0x47C520` through the already validated direct `__thiscall` pattern only for logging, and record the current cell plus the building returned from that cell. It will return `0`, allowing Syringe to replay the original call and preserve vanilla's `EAX` result.

Expected log:

```text
UpdatePosition current-cell building lookup: this=%p cell=(%d,%d) cellBuilding=%p target=%p destination=%p
```

CodeGraph plus exact source search found no Phobos/Ares ownership at `0x519AFA` or `0x519B1B`.

## Safety Constraints

Both observers must:

- require `IsCandidateSpy` and `Mission::Capture`;
- require the exact friendly `Spyable` Destination scenario;
- avoid mission, path, target, destination, position, locomotor, and occupancy mutations;
- avoid returning any nonzero continuation address;
- use complete original-instruction lengths (`0x6` and `0x5` respectively);
- retain the existing `0x519948`, `0x51BFD2`, and `0x519FF8` hooks unchanged.

## Result Interpretation

- `path-head reached` without `current-cell building lookup`: the locomotor ends at a non-building cell and `UpdatePosition` takes the `0x519AFA` re-approach/early-return path.
- `current-cell building lookup` with `cellBuilding=null`: the infantry reaches a foundation/entry cell that does not directly contain the building object.
- `current-cell building lookup` with a different building: the path terminates on the wrong occupied cell.
- `current-cell building lookup` with `cellBuilding == Target == Destination` but no `EC4 check`: the remaining identity/owner branch between `0x519B20` and `0x519FF8` is responsible.
- neither observer after movement ends: the locomotor stops before either final `UpdatePosition` boundary.

## Alternatives Rejected

1. Adding only the `0x519B1B` observer could require another run if the earlier `0x519AFA` branch is taken.
2. Forcing `UpdatePosition` to use Destination when current-cell lookup fails would change gameplay before the actual failing branch is identified.
3. Teleporting or manually setting cell occupancy would bypass locomotor bookkeeping and repeat earlier crash risks.

## Verification

The PowerShell checker will require both exact hook declarations, register sources, strict filters, log formats, direct `0x47C520` call, and `return 0`. It will reject mutation APIs inside both hook bodies.

Release and Debug Win32 builds must pass. Debug object-code inspection must confirm complete hook declarations and the direct `0x47C520` diagnostic call. Deployment must use the game-process guard, built/deployed SHA256 equality, and unchanged Phobos tracked/staged diffs.
