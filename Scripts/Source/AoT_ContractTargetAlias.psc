Scriptname AoT_ContractTargetAlias extends ReferenceAlias
{The Boss of the contract (alias 2): its death closes the contract by function call (D012).}

Event OnDeath(Actor akKiller)
	Quest q = GetOwningQuest()
	If !q || q.GetStage() < 20 || q.IsStageDone(100)
		Return
	EndIf
	AoT_Contract c = q as AoT_Contract
	If c
		Debug.Trace("[AoT-F9] Boss died on " + q)
		c.TryComplete()
	EndIf
EndEvent