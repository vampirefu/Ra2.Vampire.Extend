$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Ra2.Vampire.Extend\dllmain.cpp'
$source = Get-Content -LiteralPath $sourcePath -Raw

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains `
    -Text $source `
    -Pattern 'return\s+pThis\s*&&\s*pThis->Type[\s\S]*pThis->Type->Agent[\s\S]*pThis->Type->Infiltrate[\s\S]*!pThis->Type->Engineer;' `
    -Message 'Spy identification must require Agent + Infiltrate and exclude Engineer.'

Assert-Contains `
    -Text $source `
    -Pattern '#include\s*<EventClass\.h>' `
    -Message 'Planning Capture authorization requires EventClass.h.'

Assert-Contains `
    -Text $source `
    -Pattern '#include\s*<WaypointPathClass\.h>' `
    -Message 'Path-only self-steal authorization requires WaypointPathClass.h.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+InfantryClass\*\s+g_SpySelfSteal_AuthorizedInfantry\s*=\s*nullptr;' `
    -Message 'Missing path-only self-steal authorized infantry context.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+BuildingClass\*\s+g_SpySelfSteal_AuthorizedBuilding\s*=\s*nullptr;' `
    -Message 'Missing path-only self-steal authorized building context.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+InfantryClass\*\s+g_SpySelfSteal_PendingInfantry\s*=\s*nullptr;' `
    -Message 'Missing pending spy context for planning authorization.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+BuildingClass\*\s+g_SpySelfSteal_PendingBuilding\s*=\s*nullptr;' `
    -Message 'Missing pending building context for planning authorization.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+bool\s+IsSpySelfStealAuthorized\(InfantryClass\*\s*pThis,\s*BuildingClass\*\s*pBuilding\)[\s\S]*g_SpySelfSteal_AuthorizedInfantry\s*==\s*pThis[\s\S]*g_SpySelfSteal_AuthorizedBuilding\s*==\s*pBuilding' `
    -Message 'Self-steal authorization must be bound to the exact infantry and building.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+TriggerSpySelfStealInfiltration\(InfantryClass\*\s*pThis,\s*BuildingClass\*\s*pBuilding\)[\s\S]*!IsSpySelfStealAuthorized\(pThis,\s*pBuilding\)[\s\S]*ClearSpySelfStealAuthorization\(\)[\s\S]*InfiltratedBy' `
    -Message 'Direct infiltration must require and consume the exact path-only authorization before calling InfiltratedBy.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x4C7462,\s*EventClass_Execute_MegaMission_AuthorizeSpySelfStealPath,\s*0x5\)' `
    -Message 'Missing planning Capture authorization hook at 0x4C7462.'

$authorizationHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x4C7462,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'GET\(TechnoClass\*,\s*pTechno,\s*EDI\);[\s\S]*GET\(EventClass\*,\s*pEvent,\s*ESI\);' `
    -Message 'The planning authorization hook must read the recipient from EDI and event from ESI.'

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'static_cast<Mission>\(pEvent->MegaMission\.Mission\)\s*!=\s*Mission::Capture[\s\S]*!pEvent->MegaMission\.IsPlanningEvent' `
    -Message 'Self-steal authorization must require a planning Capture MegaMission.'

$authorizationClearIndex = $authorizationHook.IndexOf('ClearSpySelfStealAuthorization(')
$planningCaptureCheckIndex = $authorizationHook.IndexOf('if (!pEvent')
if ($authorizationClearIndex -ge 0 -and $authorizationClearIndex -lt $planningCaptureCheckIndex) {
    throw 'The MegaMission hook must not clear authorization before confirming a planning Capture event.'
}

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'pThis->PlanningToken[\s\S]*pThis->PlanningPathIdx\s*<\s*0[\s\S]*pThis->PlanningPathIdx\s*>=\s*12' `
    -Message 'Self-steal authorization must require a valid planning token and path index.'

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'pThis->Owner->PlanningPaths\[pThis->PlanningPathIdx\][\s\S]*pPath->Waypoints\.Count\s*<=\s*0' `
    -Message 'Self-steal authorization must require at least one actual path waypoint.'

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'reinterpret_cast<BuildingClass\*\(__thiscall\*\)\(TargetClass\*\)>\(0x6E7A80\)[\s\S]*&pEvent->MegaMission\.Target[\s\S]*&pEvent->MegaMission\.Destination' `
    -Message 'Self-steal authorization must resolve both planning Capture target fields through the direct vanilla TargetClass::As_Building call.'

Assert-Contains `
    -Text $authorizationHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBuilding\)[\s\S]*g_SpySelfSteal_AuthorizedInfantry\s*=\s*pThis;[\s\S]*g_SpySelfSteal_AuthorizedBuilding\s*=\s*pBuilding;' `
    -Message 'The planning Capture event must authorize the exact infantry and building.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x4D4B20,\s*FootClass_Mission_Capture_PrepareSpySelfSteal,\s*0x6\)' `
    -Message 'Missing pre-Phobos Mission_Capture compatibility hook at 0x4D4B20.'

$preHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x4D4B20,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $preHook `
    -Pattern 'GET\(FootClass\*,\s*pFoot,\s*ECX\);' `
    -Message 'The 0x4D4B20 hook must read FootClass this from ECX before the vanilla prologue.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'pFoot->WhatAmI\(\)\s*!=\s*AbstractType::Infantry' `
    -Message 'The compatibility hook must ignore non-infantry FootClass objects.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'IsCandidateSpy\(pThis\)' `
    -Message 'The compatibility hook must only handle strict spies.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'auto\s+const\s+pBld\s*=\s*g_SpySelfSteal_AuthorizedBuilding;' `
    -Message 'The compatibility hook must obtain the building from exact planning authorization.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBld\)' `
    -Message 'The compatibility hook must validate the friendly Spyable building scenario.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'IsSpySelfStealAuthorized\(pThis,\s*pBld\)' `
    -Message 'The Capture hook must require the authorization captured from the planning event.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'pThis->SetTarget\(pBld\);' `
    -Message 'The compatibility hook must set Target before the Phobos hook can clear Destination.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'pThis->SetDestination\(nullptr,\s*false\);[\s\S]*pThis->SetTarget\(pBld\);' `
    -Message 'The pre-Phobos hook must clear the queued Destination before setting Target.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'Mission_Capture prehook: reactivating friendly spy destination before Phobos' `
    -Message 'The compatibility hook must log the one-time Capture destination reactivation.'

foreach ($pattern in @('QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(')) {
    if ($preHook -match $pattern) {
        throw "The pre-Phobos hook must not mutate paths or missions; found: $pattern"
    }
}

$clearDestinationCount = [regex]::Matches($preHook, 'pThis->SetDestination\(nullptr,\s*false\);').Count
if ($clearDestinationCount -ne 1) {
    throw "Expected exactly one one-time Destination clear in the prehook, found $clearDestinationCount."
}

$setTargetCount = [regex]::Matches($source, 'pThis->SetTarget\(pBld\);').Count
if ($setTargetCount -ne 1) {
    throw "Expected exactly one friendly-spy SetTarget call in the prehook, found $setTargetCount."
}

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

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519948,\s*InfantryClass_UpdatePosition_LogSpyCaptureMovement,\s*0xA\)' `
    -Message 'Missing Capture arrival hook at 0x519948.'

$captureMovementHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519948,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' `
    -Message 'The 0x519948 arrival hook must read InfantryClass this from ESI.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'ContinueBuildingArrival\s*=\s*0x519B3E' `
    -Message 'The arrival hook must continue at vanilla building-arrival handling 0x519B3E.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'GET_STACK\(CellClass\*,\s*pCell,\s*0x14\);' `
    -Message 'The movement trace must read the current CellClass from stack offset 0x14.'

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

if ($captureMovementHook -match 'IsSpySelfStealAuthorized') {
    throw 'The movement trace must not require authorization; authorization is consumed only at final infiltration/effects.'
}

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'pThis->Target\s*!=\s*pBld' `
    -Message 'The arrival hook must require Target and Destination to be the same building.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'unitCell\s*=\s*pThis->GetMapCoords\(\);[\s\S]*destinationCell\s*=\s*pBld->GetMapCoords\(\);' `
    -Message 'The movement trace must read unit and destination map cells.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'reinterpret_cast<BuildingClass\*\(__thiscall\*\)\(CellClass const\*\)>\(0x47C520\)\(pCell\)' `
    -Message 'The movement trace must resolve the current-cell building through the direct vanilla call.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'UpdatePosition Capture movement: this=%p target=%p destination=%p unitCell=\(%d,%d\) destinationCell=\(%d,%d\) currentCellBuilding=%p queued=%d status=%d' `
    -Message 'The movement trace must log both cells, current-cell building, and mission state.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'pCellBld\s*!=\s*pBld' `
    -Message 'The arrival hook must only redirect from a foundation cell belonging to Destination.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'R->EDI\(pBld\);[\s\S]*return\s+ContinueBuildingArrival;' `
    -Message 'The arrival hook must carry the building in EDI into vanilla arrival handling.'

Assert-Contains `
    -Text $captureMovementHook `
    -Pattern 'UpdatePosition Capture arrival: entering vanilla building handling' `
    -Message 'The qualifying arrival redirect must log its decision.'

foreach ($pattern in @('SetDestination\(', 'SetTarget\(', 'QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(', 'StopMoving\(', 'Locomotor->')) {
    if ($captureMovementHook -match $pattern) {
        throw "The Capture movement diagnostic hook must remain read-only; found: $pattern"
    }
}

foreach ($address in @('0x519AFA', '0x519B1B', '0x519B20')) {
    if ($source -match "DEFINE_HOOK\($address,") {
        throw "Invalid or crash-prone UpdatePosition hook must be removed: $address"
    }
}

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x51BFD2,\s*InfantryClass_IsCellOccupied_AllowSpySelfStealDestination,\s*0x6\)' `
    -Message 'Missing safe IsCellOccupied spy self-steal destination hook at 0x51BFD2.'

Assert-Contains `
    -Text $source `
    -Pattern '#include\s*<CellClass\.h>' `
    -Message 'The IsCellOccupied hook requires CellClass.h.'

Assert-Contains `
    -Text $source `
    -Pattern '#include\s*<RulesClass\.h>' `
    -Message 'Manual self-steal effects require RulesClass.h.'

$occupancyHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x51BFD2,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'reinterpret_cast<BuildingClass\*\(__thiscall\*\)\(CellClass const\*\)>\(0x47C520\)\(pDestCell\)' `
    -Message 'The Debug-safe occupancy hook must call vanilla CellClass::GetBuilding at 0x47C520 directly.'

if ($occupancyHook -match 'pDestCell->GetBuilding\(\)') {
    throw 'The occupancy hook must not call the broken Debug YRPP CellClass::GetBuilding thunk.'
}

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'MoveOK\s*=\s*0x51C02D' `
    -Message 'The occupancy exception must use vanilla balanced Move::OK epilogue 0x51C02D.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*EBP\);' `
    -Message 'The 0x51BFA8 hook must read InfantryClass this from EBP.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'GET\(CellClass\*,\s*pDestCell,\s*ECX\);' `
    -Message 'The 0x51BFA8 hook must read the candidate CellClass from ECX.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern '!IsCandidateSpy\(pThis\)[\s\S]*pThis->CurrentMission\s*!=\s*Mission::Capture[\s\S]*!pDestCell' `
    -Message 'The occupancy exception must require a strict spy in Mission::Capture and a candidate cell.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern '!pBld[\s\S]*pBld->IsStrange\(\)[\s\S]*pThis->Target\s*!=\s*pBld[\s\S]*pThis->Destination\s*!=\s*pBld[\s\S]*!IsSpySelfStealScenario\(pThis,\s*pBld\)' `
    -Message 'The occupancy exception must reject invalid buildings and require exact friendly Spyable Target/Destination identity.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern '!IsSpySelfStealAuthorized\(pThis,\s*pBld\)' `
    -Message 'The occupancy exception must require path-only self-steal authorization.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'IsCellOccupied: allowing spy self-steal destination cell' `
    -Message 'The occupancy exception must log its strictly filtered allowance.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'return\s+MoveOK;' `
    -Message 'The qualifying occupancy path must return the vanilla Move::OK epilogue.'

Assert-Contains `
    -Text $occupancyHook `
    -Pattern 'return\s+0;' `
    -Message 'Non-qualifying occupancy checks must continue through vanilla logic.'

foreach ($address in @('0x51BFA2', '0x51BFA8')) {
    if ($source -match "DEFINE_HOOK\($address,") {
        throw "The local plugin must not hook unsafe or Phobos-owned IsCellOccupied address: $address"
    }
}

foreach ($pattern in @(
    'SetDestination\(',
    'SetTarget\(',
    'QueueMission\(',
    'NextMission\(',
    'ClearNavigationList\(',
    'ApproachTarget\(',
    'StopMoving\(',
    'SetLocation\(',
    'SetPosition\(',
    'SetMapCoords\(',
    'Limbo\(',
    'Unlimbo\(',
    'Mark\(',
    'Unmark\(',
    'Locomotor->',
    'pThis->(?:CurrentMission|QueuedMission|MissionStatus|Target|Destination)\s*=(?!=)'
)) {
    if ($occupancyHook -match $pattern) {
        throw "The occupancy exception must not mutate missions, paths, targets, destinations, positions, locomotor, or occupancy state; found: $pattern"
    }
}

foreach ($address in @('0x4D4B43', '0x519D53', '0x709A40', '0x709A63', '0x709A71', '0x6385C0')) {
    if ($source -match "DEFINE_HOOK\($address,") {
        if ($address -in @('0x709A40', '0x709A63', '0x709A71', '0x6385C0')) {
            continue
        }
        throw "Experimental or diagnostic hook must be removed from final build: $address"
    }
}

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+LogPlanningAdvance\(const\s+char\*\s+stage,\s*TechnoClass\*\s+pTechno,\s*int\s+result\)' `
    -Message 'Missing shared read-only planning-advance logging helper.'

Assert-Contains `
    -Text $source `
    -Pattern 'Planning advance: stage=%s this=%p result=%d current=%d queued=%d target=%p destination=%p token=%p nodes=%d flags=%d,%d,%d,%d path=%d waypoint=%d nav=%d' `
    -Message 'Planning diagnostics must emit comparable token, mission, path and navigation state.'

foreach ($diagnostic in @(
    @{ Address = '0x709A40'; Name = 'TechnoClass_ProceedToNextPlanningWaypoint_Log'; Size = '0x9'; Register = 'ECX'; Stage = 'ProceedToNextPlanningWaypoint' },
    @{ Address = '0x709A63'; Name = 'TechnoClass_RefreshMegaMission_Log'; Size = '0x6'; Register = 'ESI'; Stage = 'RefreshMegaMission' },
    @{ Address = '0x709A71'; Name = 'TechnoClass_CanUseWaypoint_Log'; Size = '0x6'; Register = 'ESI'; Stage = 'CanUseWaypoint' },
    @{ Address = '0x6385C0'; Name = 'TechnoClass_TryNextPlanningTokenNode_Log'; Size = '0x6'; Register = 'ECX'; Stage = 'TryNextPlanningTokenNode' }
)) {
    Assert-Contains `
        -Text $source `
        -Pattern "DEFINE_HOOK\($($diagnostic.Address),\s*$($diagnostic.Name),\s*$($diagnostic.Size)\)" `
        -Message "Missing planning diagnostic hook at $($diagnostic.Address)."

    $hook = [regex]::Match(
        $source,
        "DEFINE_HOOK\($($diagnostic.Address),[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)",
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    ).Value

    Assert-Contains `
        -Text $hook `
        -Pattern "GET\(TechnoClass\*,\s*pThis,\s*$($diagnostic.Register)\);[\s\S]*LogPlanningAdvance\(`"$($diagnostic.Stage)`"" `
        -Message "Planning diagnostic $($diagnostic.Address) must use the verified $($diagnostic.Register) unit register."

    foreach ($forbidden in @('SetTarget\(', 'SetDestination\(', 'QueueMission\(', 'NextMission\(', 'ClearNavigationList\(', 'ApproachTarget\(', 'TryNextPlanningTokenNode\(')) {
        if ($diagnostic.Address -eq '0x6385C0' -and $forbidden -in @('SetTarget\(', 'SetDestination\(')) {
            continue
        }
        if ($hook -match $forbidden) {
            throw "Planning diagnostic $($diagnostic.Address) must remain read-only; found: $forbidden"
        }
    }
}

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+AuthorizeSpySelfStealPlanningPath\(FootClass\*\s+pThis\)[\s\S]*pThis->WhatAmI\(\)\s*!=\s*AbstractType::Infantry[\s\S]*pThis->PlanningToken->PlanningNodes\.Count\s*<\s*2[\s\S]*static_cast<InfantryClass\*>\(pThis\)[\s\S]*pSpy\s*!=\s*g_SpySelfSteal_PendingInfantry[\s\S]*IsSpySelfStealScenario\(pSpy,\s*g_SpySelfSteal_PendingBuilding\)[\s\S]*g_SpySelfSteal_AuthorizedInfantry\s*=\s*pSpy;[\s\S]*g_SpySelfSteal_AuthorizedBuilding\s*=\s*g_SpySelfSteal_PendingBuilding;' `
    -Message 'Planning authorization must bind the pending exact pair only after at least two planning nodes exist.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x6385C0,\s*TechnoClass_TryNextPlanningTokenNode_Log,\s*0x6\)[\s\S]*AuthorizeSpySelfStealPlanningPath\(static_cast<FootClass\*>\(pThis\)\)' `
    -Message 'Planning authorization must occur before the verified planning node consumption point.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+PrepareSpySelfStealFinalPlanningNode\(FootClass\*\s+pThis\)[\s\S]*PlanningNodes\.Count\s*!=\s*1[\s\S]*IsSpySelfStealAuthorized\(pSpy,\s*pBuilding\)[\s\S]*IsSpySelfStealScenario\(pSpy,\s*pBuilding\)[\s\S]*pSpy->SetTarget\(pBuilding\);[\s\S]*pSpy->SetDestination\(pBuilding,\s*true\);' `
    -Message 'The final planned Capture node must restore the exact authorized building target and destination.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x6385C0,\s*TechnoClass_TryNextPlanningTokenNode_Log,\s*0x6\)[\s\S]*PrepareSpySelfStealFinalPlanningNode\(static_cast<FootClass\*>\(pThis\)\)' `
    -Message 'The final planned Capture node must be prepared before it is consumed.'

Assert-Contains `
    -Text $source `
    -Pattern 'g_SpySelfSteal_PendingInfantry\s*=\s*pThis;[\s\S]*g_SpySelfSteal_PendingBuilding\s*=\s*pBuilding;' `
    -Message 'The forced friendly Capture action must retain an exact pending spy/building pair.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x51EE4E,\s*InfantryClass_WhatAction_SpySelfSteal,\s*0x6\)' `
    -Message 'The friendly spy mouse-action hook must remain enabled.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+TriggerSpySelfStealInfiltration\(InfantryClass\*\s*pThis,\s*BuildingClass\*\s*pBuilding\)' `
    -Message 'Missing helper that directly invokes the infiltration call for self-steal.'

Assert-Contains `
    -Text $source `
    -Pattern 'reinterpret_cast<void\(__thiscall\*\)\(BuildingClass\*,\s*HouseClass\*\)>\(0x4571E0\)\(pBuilding,\s*pThis->Owner\)' `
    -Message 'Self-steal must call the Ares/Phobos-compatible BuildingClass::InfiltratedBy entry with the spy owner house.'

Assert-Contains `
    -Text $source `
    -Pattern 'case\s+AbstractType::InfantryType:[\s\S]*?pThis->Owner->BarracksInfiltrated\s*=\s*true;' `
    -Message 'Self-stealing a barracks must grant the vanilla barracks infiltration effect.'

Assert-Contains `
    -Text $source `
    -Pattern 'case\s+AbstractType::UnitType:[\s\S]*?pThis->Owner->WarFactoryInfiltrated\s*=\s*true;' `
    -Message 'Self-stealing a war factory must grant the vanilla war-factory infiltration effect.'

Assert-Contains `
    -Text $source `
    -Pattern 'pThis->Owner->RecheckTechTree\s*=\s*true;' `
    -Message 'Manual factory infiltration effects must request a tech-tree refresh.'

Assert-Contains `
    -Text $source `
    -Pattern 'RulesClass::Instance->BuildTech\.FindItemIndex\(pBuilding->Type\)\s*>=\s*0' `
    -Message 'Self-stealing a battle lab must be detected via Rules BuildTech.'

Assert-Contains `
    -Text $source `
    -Pattern 'Side0TechInfiltrated\s*=\s*true' `
    -Message 'Battle-lab self-steal must grant Allied stolen-tech state.'

Assert-Contains `
    -Text $source `
    -Pattern 'Side1TechInfiltrated\s*=\s*true' `
    -Message 'Battle-lab self-steal must grant Soviet stolen-tech state.'

Assert-Contains `
    -Text $source `
    -Pattern 'Side2TechInfiltrated\s*=\s*true' `
    -Message 'Battle-lab self-steal must grant Yuri stolen-tech state.'

Assert-Contains `
    -Text $source `
    -Pattern 'RulesClass::Instance->BuildPower\.FindItemIndex\(pBuilding->Type\)\s*>=\s*0' `
    -Message 'Self-stealing a power plant must be detected via Rules BuildPower.'

Assert-Contains `
    -Text $source `
    -Pattern 'reinterpret_cast<void\(__thiscall\*\)\(HouseClass\*,\s*int\)>\(0x50BC90\)\(pThis->Owner,\s*RulesClass::Instance->SpyPowerBlackout\)' `
    -Message 'Power-plant self-steal must call the vanilla spy power blackout routine directly.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519B58,\s*InfantryClass_UpdatePosition_SpySelfSteal_SkipEngineerPath,\s*0x6\)' `
    -Message 'Missing spy self-steal engineer-path bypass hook at 0x519B58.'

$skipEngineerPathHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x519B58,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'GET\(InfantryClass\*,\s*pThis,\s*ESI\);' `
    -Message 'The 0x519B58 hook must read InfantryClass this from ESI.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'GET\(BuildingClass\*,\s*pBuilding,\s*EDI\);' `
    -Message 'The 0x519B58 hook must read BuildingClass from EDI.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBuilding\)' `
    -Message 'The 0x519B58 hook must validate the friendly Spyable scenario.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern '!IsSpySelfStealAuthorized\(pThis,\s*pBuilding\)' `
    -Message 'The 0x519B58 hook must require path-only self-steal authorization.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'ContinueAfterInfiltration\s*=\s*0x51A010' `
    -Message 'The 0x519B58 hook must continue after the vanilla infiltration call.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'TriggerSpySelfStealInfiltration\(pThis,\s*pBuilding\)' `
    -Message 'The 0x519B58 hook must directly invoke the self-steal infiltration helper.'

Assert-Contains `
    -Text $skipEngineerPathHook `
    -Pattern 'return\s+0;' `
    -Message 'Non-qualifying 0x519B58 checks must continue through vanilla logic.'

if ($skipEngineerPathHook -match '0x519FF8|0x51A002') {
    throw 'The 0x519B58 hook must not jump to another hook/infiltration entry; call infiltration directly and continue at 0x51A010.'
}

foreach ($pattern in @(
    'SetDestination\(',
    'SetTarget\(',
    'QueueMission\(',
    'NextMission\(',
    'ClearNavigationList\(',
    'ApproachTarget\(',
    'StopMoving\(',
    'SetLocation\(',
    'SetPosition\(',
    'SetMapCoords\(',
    'Limbo\(',
    'Unlimbo\(',
    'Mark\(',
    'Unmark\(',
    'Locomotor->',
    'pThis->(?:CurrentMission|QueuedMission|MissionStatus|Target|Destination)\s*=(?!=)'
)) {
    if ($skipEngineerPathHook -match $pattern) {
        throw "The 0x519B58 hook must not mutate missions, paths, targets, destinations, positions, locomotor, or occupancy state; found: $pattern"
    }
}

if ($source -match 'DEFINE_HOOK\(0x519FF8,') {
    throw 'The local final infiltration hook overlaps Ares 3.0p1 at 0x519FF8 and must remain removed.'
}

Assert-Contains `
    -Text $source `
    -Pattern 'Ra2\.Vampire\.Extend\.log' `
    -Message 'Debug diagnostics must continue to use the local log file.'

# ---------------------------------------------------------------------------
# InfiltratedBy flag-force hook (0x45723C)
# ---------------------------------------------------------------------------
Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x45723C,\s*BuildingClass_InfiltratedBy_ForceSelfStealFlag,\s*0x6\)' `
    -Message 'Missing InfiltratedBy flag-force hook at 0x45723C.'

$infiltratedByHook = [regex]::Match(
    $source,
    'DEFINE_HOOK\(0x45723C,[\s\S]*?(?=^DEFINE_HOOK\(|^// =|\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
).Value

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'GET\(BuildingClass\*,\s*pBuilding,\s*EBP\);' `
    -Message 'The 0x45723C hook must read EBP for diagnostics.'

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern '!g_SpySelfSteal_Infantry\s*\|\|\s*!g_SpySelfSteal_Building' `
    -Message 'The 0x45723C hook must require the saved self-steal context.'

if ($infiltratedByHook -match 'pBuilding\s*!=\s*g_SpySelfSteal_Building') {
    throw 'The 0x45723C hook must not depend on EBP matching the saved building; Ares can change this frame.'
}

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'R->Stack8\(0x13,\s*static_cast<BYTE>\(1\)\)' `
    -Message 'The 0x45723C hook must force the infiltration flag at [ESP+0x13] to 1.'

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'InfiltratedBy: forcing infiltration flag for spy self-steal, ebpBuilding=%p savedBuilding=%p' `
    -Message 'The 0x45723C hook must log EBP and the saved building when forcing the flag.'

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'g_SpySelfSteal_Infantry\s*=\s*nullptr;' `
    -Message 'The 0x45723C hook must clear the saved infantry pointer after use.'

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'g_SpySelfSteal_Building\s*=\s*nullptr;' `
    -Message 'The 0x45723C hook must clear the saved building pointer after use.'

Assert-Contains `
    -Text $infiltratedByHook `
    -Pattern 'return\s+0;' `
    -Message 'The 0x45723C hook must return 0 to continue vanilla execution.'

# Global context variables must be declared
Assert-Contains `
    -Text $source `
    -Pattern 'static\s+InfantryClass\*\s+g_SpySelfSteal_Infantry\s*=\s*nullptr;' `
    -Message 'Missing g_SpySelfSteal_Infantry global context variable.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+BuildingClass\*\s+g_SpySelfSteal_Building\s*=\s*nullptr;' `
    -Message 'Missing g_SpySelfSteal_Building global context variable.'

Assert-Contains `
    -Text $source `
    -Pattern 'static\s+void\s+ClearSpySelfStealInfiltrationContext\(\)\s*\{\s*g_SpySelfSteal_Infantry\s*=\s*nullptr;\s*g_SpySelfSteal_Building\s*=\s*nullptr;\s*\}' `
    -Message 'The self-steal context clear helper must null both saved pointers.'

# The direct-call helper must save the context before calling InfiltratedBy.
Assert-Contains `
    -Text $source `
    -Pattern 'g_SpySelfSteal_Infantry\s*=\s*pThis;' `
    -Message 'The self-steal infiltration helper must save the infantry pointer for InfiltratedBy.'

Assert-Contains `
    -Text $source `
    -Pattern 'g_SpySelfSteal_Building\s*=\s*pBuilding;' `
    -Message 'The self-steal infiltration helper must save the building pointer for InfiltratedBy.'

Write-Host 'Spy self-steal source checks passed.'
