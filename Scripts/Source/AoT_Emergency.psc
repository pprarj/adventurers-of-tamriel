Scriptname AoT_Emergency extends AoT_Contract
{The A to S emergency call (Fase 9 E3, D040). Offered only when the points enable the promotion
and the cut asks for the call (ExamKind 2). It stays out of the ledger: a win calls
AoT_Core.Promote; a loss or a flight takes no points and no rank (D-21). State in aot_emg_ keys:
aot_emg_state (1 = a call is taken), aot_emg_rank, aot_emg_quest, aot_emg_day. Promote is called
only from the Boss death, never from a load, and Heal releases a call whose quest is gone.}

Function TryOpen()
	If !IsRunning() || GetStage() >= 20
		Return
	EndIf
	If StorageUtil.GetIntValue(None, "aot_emg_state", 0) == 1 && StorageUtil.GetFormValue(None, "aot_emg_quest", None) != self as Quest
		Debug.Trace("[AoT-F9] emergency: another call is already taken")
		Return
	EndIf
	StorageUtil.SetIntValue(None, "aot_emg_state", 1)
	StorageUtil.SetIntValue(None, "aot_emg_rank", AoT_Core.GetRank())
	StorageUtil.SetFormValue(None, "aot_emg_quest", self as Quest)
	StorageUtil.SetFloatValue(None, "aot_emg_day", Utility.GetCurrentGameTime())
	Debug.Trace("[AoT-F9] emergency taken " + self + " rank=" + AoT_Core.GetRank() + " dungeon=" + DungeonLocation())
	MirrorStage(20)
	SetObjectiveDisplayed(20)
EndFunction

Bool Function IsTaken()
	Return StorageUtil.GetIntValue(None, "aot_emg_state", 0) == 1 && StorageUtil.GetFormValue(None, "aot_emg_quest", None) == self as Quest
EndFunction

Bool Function TryComplete()
	If !IsTaken()
		Return False
	EndIf
	Int rank = StorageUtil.GetIntValue(None, "aot_emg_rank", -1)
	Bool promoted = False
	If rank == AoT_Core.GetRank() && AoT_Core.ExamKind(rank) == 2
		promoted = AoT_Core.Promote()
	EndIf
	Debug.Trace("[AoT-F9] emergency won " + self + " rank=" + rank + " promoted=" + promoted + " now=" + AoT_Core.GetRank())
	_ClearState()
	SetObjectiveCompleted(20)
	MirrorStage(100)
	Finish(0)
	Return promoted
EndFunction

Bool Function TryAbandon()
	{Flight: the call is released, nothing is taken (D-21).}
	If !IsTaken()
		Return False
	EndIf
	Debug.Trace("[AoT-F9] emergency released " + self + " rank=" + AoT_Core.GetRank() + " points=" + AoT_Core.GetPoints())
	_ClearState()
	CloseObjectives()
	MirrorStage(105)
	Finish(0)
	Return True
EndFunction

Bool Function TryExpire()
	{The call lapses after aot_emg_lapse_days game days; the same as a flight.}
	Return TryAbandon()
EndFunction

Function _ClearState() Global
	StorageUtil.UnsetIntValue(None, "aot_emg_state")
	StorageUtil.UnsetIntValue(None, "aot_emg_rank")
	StorageUtil.UnsetFormValue(None, "aot_emg_quest")
	StorageUtil.UnsetFloatValue(None, "aot_emg_day")
EndFunction

Function Heal() Global
	{Keeps the call state true to the quest after any load: a taken call whose quest stopped or
	never reached the hunt is released, and an old call lapses. Never promotes.}
	If StorageUtil.GetIntValue(None, "aot_emg_state", 0) != 1
		Return
	EndIf
	Quest q = StorageUtil.GetFormValue(None, "aot_emg_quest", None) as Quest
	AoT_Emergency e = q as AoT_Emergency
	If !e || !q.IsRunning() || q.GetStage() < 20 || q.IsStageDone(100) || q.IsStageDone(105)
		Debug.Trace("[AoT-F9] emergency state healed (quest " + q + " is not in the hunt)")
		_ClearState()
		Return
	EndIf
	Float lapse = JsonUtil.GetIntValue(AoT_ContractsCtl.ContractsPath(), "aot_emg_lapse_days", 7) as Float
	If Utility.GetCurrentGameTime() > StorageUtil.GetFloatValue(None, "aot_emg_day", 0.0) + lapse
		Debug.Trace("[AoT-F9] emergency lapsed " + q)
		e.TryExpire()
	EndIf
EndFunction