Scriptname AoT_ContractRisenAlias extends ReferenceAlias
{Fase 10 (D047), S2: the second one (alias 5 of the two-phase contract), forced in by
AoT_ContractRisen when the Boss dies. Its death closes the contract.}

Event OnDeath(Actor akKiller)
	AoT_ContractRisen c = GetOwningQuest() as AoT_ContractRisen
	If c && c.GetStage() == 30
		c.RisenDied()
	EndIf
EndEvent
