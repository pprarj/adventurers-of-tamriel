Scriptname AoT_ContractNoteAlias extends ReferenceAlias
{The contract note (alias 4). Taking it out of the board is accepting the contract (D026).}

Event OnContainerChanged(ObjectReference akNewContainer, ObjectReference akOldContainer)
	If akNewContainer != Game.GetPlayer()
		Return
	EndIf
	AoT_Contract c = GetOwningQuest() as AoT_Contract
	If c
		c.TryOpen()
	EndIf
EndEvent