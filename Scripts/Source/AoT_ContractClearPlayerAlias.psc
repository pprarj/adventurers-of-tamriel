Scriptname AoT_ContractClearPlayerAlias extends ReferenceAlias
{Fase 10 (D047), A2: the player (alias 5 of the lair contract). While the contract waits for the
lair to be cleared (stage 30), each location change counts it again (D050).}

Event OnLocationChange(Location akOldLoc, Location akNewLoc)
	AoT_ContractClear c = GetOwningQuest() as AoT_ContractClear
	If c && c.GetStage() == 30
		c.CheckCleared()
	EndIf
EndEvent
