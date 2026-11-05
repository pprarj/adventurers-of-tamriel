Scriptname AoT_ContractRelic extends AoT_Contract
{Fase 10 (D047), A3: the relic. The quest creates the relic in the chest at the end of the
Dungeon (alias 2 Chest, ref type BossContainer; alias 5 Relic). The contract closes when the
relic enters the inventory of the player after the note was taken; a relic dropped elsewhere
does not count. An offer that leaves, or an abandoned contract, takes the relic away with it.
There is no Target alias: alias 2 is the chest.}

Bool _withPlayer = False

ObjectReference Function RelicRef()
	ReferenceAlias a = GetAlias(5) as ReferenceAlias
	If a
		Return a.GetReference()
	EndIf
	Return None
EndFunction

ObjectReference Function ChestRef()
	ReferenceAlias a = GetAlias(2) as ReferenceAlias
	If a
		Return a.GetReference()
	EndIf
	Return None
EndFunction

Bool Function IsOfferable()
	Return ChestRef() && RelicRef() && NoteRef() && DungeonLocation()
EndFunction

Function RelicMoved(ObjectReference akNewContainer)
	{Called by the Relic alias on each container change.}
	_withPlayer = akNewContainer && akNewContainer == Game.GetPlayer()
	Debug.Trace("[AoT-F10] relic moved to " + akNewContainer + " on " + self + " stage=" + GetStage())
	If _withPlayer && IsRunning() && GetStage() >= 20 && !IsStageDone(100)
		TryComplete()
	EndIf
EndFunction

Function TryOpen()
	Parent.TryOpen()
	; the relic was already picked up before the note was taken
	If _withPlayer && GetStage() >= 20 && !IsStageDone(100)
		TryComplete()
	EndIf
EndFunction

Function TakeRelicAway()
	ObjectReference relic = RelicRef()
	If !relic
		Return
	EndIf
	If _withPlayer
		Game.GetPlayer().RemoveItem(relic, 1, True)
	Else
		ObjectReference chest = ChestRef()
		If chest
			chest.RemoveItem(relic, 1, True)
		EndIf
	EndIf
	relic.Delete()
	_withPlayer = False
EndFunction

Function Retire()
	If !IsRunning() || GetStage() >= 20
		Return
	EndIf
	TakeRelicAway()
	Parent.Retire()
EndFunction

Bool Function TryAbandon()
	; read before the quest stops: Stop clears the aliases
	ObjectReference relic = RelicRef()
	ObjectReference chest = ChestRef()
	Bool wasWith = _withPlayer
	Bool ok = Parent.TryAbandon()
	If ok && relic && !wasWith
		; still in the chest (or dropped): it leaves with the contract
		If chest
			chest.RemoveItem(relic, 1, True)
		EndIf
		relic.Delete()
	EndIf
	_withPlayer = False
	Return ok
EndFunction

Function Finish(Int aiId)
	_withPlayer = False
	Parent.Finish(aiId)
EndFunction
