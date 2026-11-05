Scriptname AoT_Contract extends Quest
{A generated guild contract (Fase 9, D038): one quest per archetype and hold, written by the
contract generator. The board starts it, which is only an offer (D026): the note waits in the
board. Taking the note opens the contract in the ledger (TryOpen); the death of the Boss closes
it (TryComplete); the attendant abandons it (TryAbandon). The stage only mirrors the ledger
(D012). Repeatable: the quest stops at the end and the board may offer it again, and the engine
fills the Dungeon alias again on each Start.
Aliases: 0 Hold, 1 Dungeon, 2 Target (Boss), 3 Board (external, the board quest), 4 Missive (the
note, created in the board).}

Int Property Band = 0 Auto
Int Property HoldIndex = -1 Auto
Int Property EventIndex = -1 Auto
Quest Property Counterpart Auto
{Situation contracts only (D042): the common contract of the same archetype and hold. Both fill
the same places, so the board retires its untaken offer before it starts the situation.}
Quest Property Counterpart2 Auto
{Fase 10 (D047): a second quest of the same places (the A2 lair contract has the common contract
as Counterpart and the emergency call as Counterpart2). The board never offers one while the
other runs.}
Quest Property Counterpart3 Auto
{Fase 10 (D047): a third quest of the same places (the S2 dwemer contract shares them with the
common contract, the emergency call and the A2 lair contract).}

; Stages: 0 offered, 20 hunt, 100 complete, 105 failed or abandoned, 110 retired offer.

ObjectReference Function NoteRef()
	ReferenceAlias a = GetAlias(4) as ReferenceAlias
	If a
		Return a.GetReference()
	EndIf
	Return None
EndFunction

Actor Function TargetActor()
	ReferenceAlias a = GetAlias(2) as ReferenceAlias
	If a
		Return a.GetActorReference()
	EndIf
	Return None
EndFunction

Location Function DungeonLocation()
	LocationAlias a = GetAlias(1) as LocationAlias
	If a
		Return a.GetLocation()
	EndIf
	Return None
EndFunction

Bool Function IsOfferable()
	{A started quest is worth offering only with a living Boss and a note in the board.}
	Actor t = TargetActor()
	Return t && !t.IsDead() && NoteRef() && DungeonLocation()
EndFunction

Function TryOpen()
	{The player took the note: the contract opens in the ledger and the hunt starts.}
	If !IsRunning() || GetStage() >= 20
		Return
	EndIf
	Int id = AoT_Core.FindOpenContract(self as Quest)
	If id == 0
		id = AoT_Core.OpenContract(self as Quest, Band)
	EndIf
	Debug.Trace("[AoT-F9] TryOpen " + self + " band=" + Band + " hold=" + HoldIndex + " -> id=" + id + " dungeon=" + DungeonLocation())
	If id > 0
		StorageUtil.SetFormValue(None, "aot_own_q" + id, self as Quest)
		MirrorStage(20)
		SetObjectiveDisplayed(20)
	EndIf
EndFunction

Bool Function TryComplete()
	Int id = AoT_Core.FindOpenContract(self as Quest)
	If id == 0
		Debug.Trace("[AoT-F9] TryComplete no open contract on " + self)
		Return False
	EndIf
	Bool ok = AoT_Core.CompleteContract(id)
	Debug.Trace("[AoT-F9] CompleteContract id=" + id + " -> " + ok + " points=" + AoT_Core.GetPoints())
	If ok
		SetObjectiveCompleted(20)
		MirrorStage(100)
		Finish(id)
	EndIf
	Return ok
EndFunction

Bool Function TryAbandon()
	Int id = AoT_Core.FindOpenContract(self as Quest)
	If id == 0
		Debug.Trace("[AoT-F9] TryAbandon no open contract on " + self)
		Return False
	EndIf
	Bool ok = AoT_Core.AbandonContract(id)
	Debug.Trace("[AoT-F9] AbandonContract id=" + id + " -> " + ok)
	If ok
		MirrorStage(105)
		Finish(id)
	EndIf
	Return ok
EndFunction

Bool Function TryExpire()
	{Generated contracts do not expire in Fase 9; kept for the shape of the 2b contract.}
	Return False
EndFunction

Function Retire()
	{An offer nobody took: the note leaves the board and the quest stops, free for the next offer.}
	If !IsRunning() || GetStage() >= 20
		Return
	EndIf
	ObjectReference note = NoteRef()
	ObjectReference board = StorageUtil.GetFormValue(self as Quest, "aot_offer_board", None) as ObjectReference
	If note && board
		board.RemoveItem(note, 1, True)
	EndIf
	If note
		note.Delete()
	EndIf
	MirrorStage(110)
	Stop()
	Debug.Trace("[AoT-F9] retired offer " + self)
EndFunction

Bool Function WaitStopped()
	{After Retire or Stop: wait until the engine let the quest go, so that it can start again in
	the same refresh (D042). True when it stopped within 3 s.}
	Int n = 0
	While (IsRunning() || IsStopping()) && n < 30
		Utility.Wait(0.1)
		n += 1
	EndWhile
	Return !IsRunning()
EndFunction

Function Finish(Int aiId)
	{End of a taken contract: the note leaves the player and the quest stops (repeatable).}
	ObjectReference note = NoteRef()
	If note
		Game.GetPlayer().RemoveItem(note, 1, True)
		note.Delete()
	EndIf
	If aiId > 0
		StorageUtil.UnsetFormValue(None, "aot_own_q" + aiId)
	EndIf
	Stop()
EndFunction

Function MirrorStage(Int aiStage)
	{Journal mirror only. Nothing listens to the stage, so this cannot re-enter.}
	If !IsStageDone(aiStage)
		SetStage(aiStage)
	EndIf
EndFunction