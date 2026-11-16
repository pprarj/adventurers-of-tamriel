Scriptname AoT_ContractClear extends AoT_Contract
{Fase 10 (D047, D050), A2: clear the lair. The death of the Boss closes the contract only when the
lair is clear: Location.IsCleared AND no hostile actor seen alive in the lair is still alive.
Location.IsCleared alone turns true at the death of the Boss (measured), so it is only one of the
conditions. Otherwise stage 30 asks for the rest of the lair and gives no point.
Hostile = alive, enabled, not the player, not commanded, not a teammate, hostile to the player, in
the Dungeon location (or a child). They are looked for only in the player's cell, and only while
the player is in the Dungeon location: a scan from outside sees nobody, and that zero is never read
as clear. Every hostile seen stays on a list until it is seen dead; the count is the size of the
list. Recounts run on events only: the Boss death, any actor killed (PO3 event, registered while
stage 30 waits) and the player's location changes (alias 5).
Stages: 0 offered, 20 hunt, 30 Boss dead and the lair still held, 100 complete, 105 failed or
abandoned, 110 retired offer.}

String Property SeenKey = "aot_lair_seen" AutoReadOnly

Bool _scannedInside = False

Bool Function TryComplete()
	Location dun = DungeonLocation()
	If dun && !dun.IsCleared() && !IsStageDone(30)
		; the cleared flag may be set a moment after the death event
		Utility.Wait(1.0)
	EndIf
	If !IsStageDone(30)
		StorageUtil.FormListClear(self, SeenKey)
		_scannedInside = False
	EndIf
	Int n = Recount(dun)
	If !LairClear(dun, n)
		If !IsStageDone(30)
			Debug.Trace("[AoT-F10] Boss dead, " + dun + " not cleared: stage 30 on " + self + " hostiles=" + n)
			SetObjectiveCompleted(20)
			MirrorStage(30)
			SetObjectiveDisplayed(30)
			PO3_Events_Form.RegisterForActorKilled(self)
		EndIf
		Return False
	EndIf
	Return CloseLair(dun, n)
EndFunction

Bool Function LairClear(Location akDun, Int aiHostiles)
	Return akDun && akDun.IsCleared() && _scannedInside && aiHostiles == 0
EndFunction

Bool Function CloseLair(Location akDun, Int aiHostiles)
	If IsStageDone(30)
		SetObjectiveCompleted(30)
	EndIf
	PO3_Events_Form.UnregisterForActorKilled(self)
	StorageUtil.FormListClear(self, SeenKey)
	Debug.Trace("[AoT-F10] lair cleared " + akDun + " on " + self + " hostiles=" + aiHostiles)
	Return Parent.TryComplete()
EndFunction

Int Function Recount(Location akDun)
	{Adds the hostiles of the player's cell (player inside the lair only) to the seen list, drops
	the ones now dead, disabled or no longer hostile, and returns the size of the list; -1 while
	the lair was never scanned from inside.}
	If !akDun
		Return -1
	EndIf
	Actor pl = Game.GetPlayer()
	If pl.IsInLocation(akDun)
		Actor[] arr = MiscUtil.ScanCellNPCs(pl, 0.0, None, True)
		Int i = 0
		While i < arr.Length
			If IsLairHostile(arr[i], pl, akDun)
				StorageUtil.FormListAdd(self, SeenKey, arr[i], False)
			EndIf
			i += 1
		EndWhile
		_scannedInside = True
	EndIf
	Int j = StorageUtil.FormListCount(self, SeenKey) - 1
	While j >= 0
		Actor s = StorageUtil.FormListGet(self, SeenKey, j) as Actor
		; an actor of a cell that is not loaded may read as None: it stays counted
		If s && (s.IsDead() || s.IsDisabled() || !s.IsHostileToActor(pl))
			StorageUtil.FormListRemoveAt(self, SeenKey, j)
		EndIf
		j -= 1
	EndWhile
	If !_scannedInside
		Return -1
	EndIf
	Return StorageUtil.FormListCount(self, SeenKey)
EndFunction

Bool Function IsLairHostile(Actor akActor, Actor akPlayer, Location akDun)
	If !akActor || akActor == akPlayer || akActor.IsDead() || akActor.IsDisabled()
		Return False
	EndIf
	If akActor.IsCommandedActor() || akActor.IsPlayerTeammate()
		Return False
	EndIf
	Return akActor.IsHostileToActor(akPlayer) && akActor.IsInLocation(akDun)
EndFunction

Function CheckCleared()
	{Stage 30 only: called by the player alias on a location change, and by the kill event.}
	If !IsRunning() || !IsStageDone(30) || IsStageDone(100) || IsStageDone(105)
		PO3_Events_Form.UnregisterForActorKilled(self)
		Return
	EndIf
	Location dun = DungeonLocation()
	Int n = Recount(dun)
	Debug.Trace("[AoT-F10] lair recount " + dun + " on " + self + " hostiles=" + n)
	If LairClear(dun, n)
		CloseLair(dun, n)
	EndIf
EndFunction

Event OnActorKilled(Actor akVictim, Actor akKiller)
	{PO3 kill event, registered from stage 30 until the lair closes. A kill recounts when the
	victim was on the seen list or the player is in the lair.}
	If !IsRunning() || GetStage() != 30
		PO3_Events_Form.UnregisterForActorKilled(self)
		Return
	EndIf
	Location dun = DungeonLocation()
	If dun && (StorageUtil.FormListHas(self, SeenKey, akVictim) || Game.GetPlayer().IsInLocation(dun))
		CheckCleared()
	EndIf
EndEvent

