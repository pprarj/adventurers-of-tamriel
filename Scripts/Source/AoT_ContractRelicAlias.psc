Scriptname AoT_ContractRelicAlias extends ReferenceAlias
{Fase 10 (D047), A3: the relic (alias 5). Each container change goes to the contract, which
closes when the relic reaches the player.}

Event OnContainerChanged(ObjectReference akNewContainer, ObjectReference akOldContainer)
	AoT_ContractRelic c = GetOwningQuest() as AoT_ContractRelic
	If c
		c.RelicMoved(akNewContainer)
	EndIf
EndEvent
