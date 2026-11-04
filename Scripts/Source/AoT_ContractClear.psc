Scriptname AoT_ContractClear extends AoT_Contract
{Fase 10 (D047), A2: clear the lair. The death of the Boss closes the contract only when the
Dungeon location is cleared (Location.IsCleared). Otherwise stage 30 asks for the rest of the
lair, gives no point, and the player alias (5) checks again on each location change.
Stages: 0 offered, 20 hunt, 30 Boss dead and the lair still held, 100 complete, 105 failed or
abandoned, 110 retired offer.}

Bool Function TryComplete()
	Location dun = DungeonLocation()
	If dun && !dun.IsCleared() && !IsStageDone(30)
		; the cleared flag may be set a moment after the death event (to measure, TESTPLAN)
		Utility.Wait(1.0)
	EndIf
	If dun && !dun.IsCleared()
		If !IsStageDone(30)
			Debug.Trace("[AoT-F10] Boss dead, " + dun + " not cleared: stage 30 on " + self)
			SetObjectiveCompleted(20)
			MirrorStage(30)
			SetObjectiveDisplayed(30)
		EndIf
		Return False
	EndIf
	If IsStageDone(30)
		SetObjectiveCompleted(30)
	EndIf
	Debug.Trace("[AoT-F10] lair cleared " + dun + " on " + self)
	Return Parent.TryComplete()
EndFunction

Function CheckCleared()
	{Stage 30 only: called by the player alias on a location change.}
	If !IsRunning() || !IsStageDone(30) || IsStageDone(100) || IsStageDone(105)
		Return
	EndIf
	Location dun = DungeonLocation()
	If dun && dun.IsCleared()
		TryComplete()
	EndIf
EndFunction
