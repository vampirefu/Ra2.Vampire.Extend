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
    -Pattern 'specific_cast<BuildingClass\*>\(pThis->Destination\)' `
    -Message 'The compatibility hook must obtain the building from the queued Destination.'

Assert-Contains `
    -Text $preHook `
    -Pattern 'IsSpySelfStealScenario\(pThis,\s*pBld\)' `
    -Message 'The compatibility hook must validate the friendly Spyable building scenario.'

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

if ($occupancyHook -match 'IsSpySelfStealAuthorized') {
    throw 'The occupancy exception must not require authorization; it only restores movement while final infiltration remains gated.'
}

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

foreach ($address in @('0x4D4B43', '0x4C7462', '0x519D53', '0x709A40', '0x709A63', '0x709A71', '0x6385C0')) {
    if ($source -match "DEFINE_HOOK\($address,") {
        throw "Experimental or diagnostic hook must be removed from final build: $address"
    }
}

if ($source -match 'MegaMission dispatch:' -or $source -match 'Planning advance:') {
    throw 'High-volume diagnostic logging must be removed from the final build.'
}

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

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519FF8,\s*InfantryClass_UpdatePosition_SpySelfSteal,\s*0xA\)' `
    -Message 'The final friendly infiltration hook must remain enabled.'

Assert-Contains `
    -Text $source `
    -Pattern 'DEFINE_HOOK\(0x519FF8,[\s\S]*?ContinueAfterInfiltration\s*=\s*0x51A010[\s\S]*?TriggerSpySelfStealInfiltration\(pThis,\s*pBuilding\)' `
    -Message 'The final friendly infiltration hook must directly call infiltration and continue after the call.'

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
