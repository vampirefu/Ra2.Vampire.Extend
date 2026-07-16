# Spy Self-Steal Allow Capture Destination Cell Design

## Purpose

Allow a strict spy executing `Mission::Capture` to step into the foundation cell of its exact friendly `Spyable` Target/Destination so the existing vanilla `UpdatePosition` infiltration flow can run.

## Root Cause

Runtime evidence shows that Capture initialization succeeds and movement starts:

- `Target` and `Destination` both point to the same barracks;
- `CurrentMission` is `Mission::Capture`;
- the spy moves from cell `(64,28)` to `(65,27)` while the barracks anchor is `(64,26)`;
- movement then stops and `0x519FF8` is never reached.

Vanilla `InfantryClass::IsCellOccupied` checks the candidate cell's occupants. Its allied-object branch dispatches `AbstractType::Building` directly to the `Move::No` epilogue at `0x51C7D0`. That prevents the friendly spy from entering the building foundation and therefore prevents `UpdatePosition` from resolving the cell to the target building. The existing final infiltration hook cannot run until this occupancy result is corrected.

## Crash Diagnosis

The first `0x51BFA8` implementation declared a hook size of `0x7`. Runtime then failed with `C0000005` at the invalid address `0x06581000` while the exception registers still held the querying infantry and candidate cell.

Fresh disassembly proves that `0x51BFA8` begins this instruction sequence:

```text
0x51BFA8  je 0x51BFCD             ; 2 bytes
0x51BFAA  mov eax,[esp+0x40]      ; 4 bytes
0x51BFAE  cmp eax,-1              ; 3 bytes
```

A size of `0x7` therefore saves the complete first two instructions plus only the first byte of the third instruction. Syringe documents the size as the number of original instruction bytes saved for the original-return path. Replaying seven bytes and continuing at `0x51BFAF` resumes in the middle of `cmp eax,-1`, corrupting control flow before the filtered allowance log can run.

## Selected Architecture

Move the hook to `0x51BFD2`, where the two vanilla branches from `0x51BFA8` converge. Address `0x51BFD2` is unoccupied in the checked Phobos/Ares sources, does not overlap Phobos's `0x51BFA2` hook, and starts the complete six-byte instruction `mov al,[ecx+0x124]`.

At this address:

- `EBP` is the querying `InfantryClass*`;
- `ECX` is the candidate `CellClass*`;
- returning `0` continues vanilla and replays the complete overwritten six-byte instruction;
- returning `0x51C02D` uses vanilla's balanced `Move::OK` epilogue, matching the return target already used by Phobos for its balloon-hover exception.

## Debug Thunk Crash Diagnosis

After moving to the complete `0x51BFD2/0x6` boundary, runtime reached `Mission_Capture post-SetDestination` and then failed with `C0000005` at `0x00000000`. The exception stack returns to `0x47C53B`, the indirect virtual call inside vanilla `CellClass::GetBuilding()`.

The hook frame proves that the captured candidate cell was valid at `0x1B766C10`. However, the Debug object code generated for YRPP's `JMP_THIS(0x47C520)` thunk restores `ECX` from a saved `EDI` slot after its debug prologue. It consequently passes the hook's stack frame `0x001AB098` to vanilla instead of the candidate cell. Vanilla reads a false content pointer from that stack memory and calls a null virtual-function entry. The compiler's C4731 warning for `CellClass::GetBuilding` identifies the same frame-pointer-changing thunk.

The optimized Release thunk preserves `ECX`, but deploying Release only would hide diagnostics and leave Debug builds unsafe. The selected correction is to bypass only this generated thunk and invoke the same vanilla function directly:

```cpp
auto const pBld = reinterpret_cast<BuildingClass*(__thiscall*)(CellClass const*)>(0x47C520)(pDestCell);
```

This explicit fixed-address `__thiscall` pattern is already used in Phobos for other vanilla methods. It preserves the exact vanilla `GetBuilding` behavior while making the compiler load `pDestCell` into `ECX` immediately before the call in both Debug and Release.

The hook will return `0x51C02D` only when all conditions hold:

1. the unit passes `IsCandidateSpy`;
2. its current mission is `Mission::Capture`;
3. the candidate cell contains a building;
4. that building is exactly both `pThis->Target` and `pThis->Destination`;
5. `IsSpySelfStealScenario` confirms a friendly `Spyable` target;
6. the building is not strange/invalid.

Every other call returns `0` and executes the original occupancy logic. The hook does not set position, target, destination, mission, locomotor state, navigation queues, or occupancy data.

## Interaction with Existing Hooks

- `0x51EE4E` continues to expose Capture action for the friendly spy.
- `0x4D4B20` continues to rebuild Target/Destination after the planning path becomes current.
- `0x51BFD2` permits only the exact self-steal destination building cell.
- `0x519FF8` continues to bypass the final owner capability gate and hand control to Phobos's `0x51A002` trigger hook plus vanilla infiltration.

The temporary `0x4D4BC7` and `0x519948` traces remain enabled for the first repaired runtime test. They will be removed in a separate cleanup after entry and stability are verified.

## Alternatives Rejected

1. Keeping `0x51BFA8` with size `0x7` is invalid because it splits `cmp eax,-1` and has already produced a reproducible control-flow crash.
2. Keeping `0x51BFA8` with size `0x6` would cover complete instructions, but its original-return path still has to replay a relative conditional branch immediately adjacent to Phobos. The convergence point avoids both concerns.
3. Deploying Release only avoids the broken Debug thunk but removes the runtime diagnostics needed to validate entry and leaves Debug artifacts unsafe.
4. Reimplementing `GetBuilding` by traversing `CellClass` content would duplicate vanilla bridge/content semantics and create a larger behavior surface.
5. Hooking `0x51BFA2` would overlap Phobos and make hook order undefined.
6. Forcing the spy's position or teleporting it into the building would bypass locomotor and cell bookkeeping, recreating the crash risk observed in earlier attempts.
7. Broadly allowing allied buildings would affect unrelated infantry, garrisoning, repair, and movement behavior.

## Testing and Safety

The PowerShell source check will require the exact `0x51BFD2` hook with size `0x6`, `EBP`/`ECX` register sources, the direct `__thiscall` to `0x47C520`, all strict identity and scenario conditions, and the `0x51C02D` return. It will reject `pDestCell->GetBuilding()` inside this hook, reject gameplay mutation calls, and forbid local hooks at both `0x51BFA2` and the crash-prone `0x51BFA8` address.

After the Debug build, object-code inspection must prove that the occupancy hook loads the captured `pDestCell` into `ECX` and calls address `0x47C520` directly rather than calling the generated `CellClass::GetBuilding` symbol.

Release and Debug Win32 builds must pass. Deployment must abort while an AGWar process from the game directory is running. The deployed Debug DLL hash must match the built artifact, and Phobos tracked and staged diffs must remain empty.

## Runtime Success Criteria

With engineer and spy queued through waypoint A to the damaged friendly barracks:

- the engineer enters normally;
- the spy reaches `UpdatePosition EC4 check` and `triggering infiltration`;
- the spy disappears into the building and the infiltration effect executes;
- the game remains stable after entry;
- ordinary non-spy movement and non-target friendly buildings remain unaffected.
