Scriptname AoT_ContractRisenAlias extends ReferenceAlias
{Fase 10 (D047), S2: the second one (alias 5 of the two-phase contract), forced in by
AoT_ContractRisen when the Boss dies. Its death closes the contract.}

Event OnDeath(Actor akKiller)
	AoT_ContractRisen c = GetOwningQuest() as AoT_ContractRisen
	If c && c.GetStage() == 30
		If JsonUtil.GetIntValue(AoT_Crystals.TablePath(), "aot_crystal_large_on_risen", 0) == 1
			AoT_Crystals.GiveLarge(c, GetActorReference(), "risen")
		EndIf
		c.RisenDied()
	EndIf
EndEvent
